#!/bin/bash
# Esto deberia ayudar 
export MSYS2_ARG_CONV_EXCL="*"
# Aprovecharemos el script del laboratorio 1

echo "|== iniciando ==|"
# =================================
# SECCION 0: DEFINICION DE VARIABLES
VPC_CIDR="10.0.0.0/16" 
VPC_NAME="lab2"
REGION="us-east-1" 
export AWS_DEFAULT_REGION=$REGION # Para asegurar la region en cada comando
export PAGER=cat # Para que la terminal no se cuelgue con json de confirmacion
export AWS_PAGER=""
export CLUSTER=lab2
export APP=mi-emprendimiento
export SEMANTIC_VERSION=1.0
export REPO_NAME=${VPC_NAME}-${APP}
export ACCOUNT=$(aws sts get-caller-identity \
    --query Account \
    --output text)

# =================================
# SECCION 1: Creacion ROL IAM
echo "Verificando rol ecsTaskExecutionRole..."
ROLE_EXISTS=$(aws iam get-role --role-name ecsTaskExecutionRole --query 'Role.RoleName' --output text 2>/dev/null)
if [ "$ROLE_EXISTS" == "ecsTaskExecutionRole" ]; then
    echo "OK: El rol ecsTaskExecutionRole ya existe."
else
    echo "El rol no existe, creando..."
    cat > /tmp/ecs-trust-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
JSON
    aws iam create-role \
        --role-name ecsTaskExecutionRole \
        --assume-role-policy-document file:///tmp/ecs-trust-policy.json

    aws iam attach-role-policy \
        --role-name ecsTaskExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

    echo "OK: Rol ecsTaskExecutionRole creado y politica adjuntada."
    rm -f /tmp/ecs-trust-policy.json
fi



# =================================
# SECCION 2: CREACION VPC + SUBNETS Publicas
echo "Creando VPC con rango ${VPC_CIDR}"
# Creamos la VPC con el CIDR indicado previamente y guardamos su ID
export VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --query 'Vpc.VpcId' --output text)


# Se hace validacion, para ver si se creo la vpc (NO TENIA IDEA QUE SE PODIAN GENERAR BLOQUES IF/ELSE ACA)
# Primero -z valida  si exite el dato, mientras None, valida si aws retorno "None", lo cual tambien es un error
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    # Si VPC_ID esta vacio (osea no se creo) cierra todo
    echo "ERROR: No se pudo crear la VPC."
    exit 1
else
    echo "OK: VPC creada con ID: $VPC_ID"
fi

# asignacion de nombre a la vpc
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
echo "$VPC_ID ahora se llama $VPC_NAME"

# Permite asignacion de DNS,esto ayuda a identificar las maquinas de la VPC cambiando Ip por URL
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames


echo "Iniciando creacion de subnet publica en zona A"
# Creamos una subnet en el mismo rango de la VPC, esta sera la subnet Publica, habilitada en la region, hardcodeamos que sea 'us-east-1a'
export SUBNET_PUB_A=$(aws ec2 create-subnet\
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${REGION}a \
    --query 'Subnet.SubnetId' \
    --output text)
# captura de id a ver si hay error, si no veo mensajes conforma pasa el tiempo me da ansiedad
if [ -z "$SUBNET_PUB_A" ] || [ "$SUBNET_PUB_A" == "None" ]; then
    echo "ERROR: No se pudo crear la SUBNET Publica en zona A."
    exit 1
else
    echo "OK: SUBNET Publica creada con ID: $SUBNET_PUB_A"
fi
# Aprovecho que VPC_NAME es lab2 para asignar nombres de forma mas consistente
aws ec2 create-tags --resources $SUBNET_PUB_A --tags Key=Name,Value=${VPC_NAME}-Subnet-Pub-A
# Asigna Ip publicas automaticamente
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_A --map-public-ip-on-launch

# Para aprovechar el ALB hacemos una segunda subnetPublica, la cual estara asignada a la region B
echo "Iniciando creacion de subnet publica en zona B"
export SUBNET_PUB_B=$(aws ec2 create-subnet\
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${REGION}b \
    --query 'Subnet.SubnetId' \
    --output text)
if [ -z "$SUBNET_PUB_B" ] || [ "$SUBNET_PUB_B" == "None" ]; then
    echo "ERROR: No se pudo crear la SUBNET Publica en zona B."
    exit 1
else
    echo "OK: SUBNET Publica creada con ID: $SUBNET_PUB_B"
fi
aws ec2 create-tags --resources $SUBNET_PUB_B --tags Key=Name,Value=${VPC_NAME}-Subnet-Pub-B
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB_B --map-public-ip-on-launch


# ================================
# SECCION 3: CREAR IGW
# ================================
echo "Iniciando creacion de Internet Gateway"
# Creamos una internet gateway, nada mas que comentar aca
export IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

# Capturar de errores
if [ -z "$IGW_ID" ] || [ "$IGW_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Internet Gateway"
    exit 1

else
    echo "OK: Internet Gateway creado con ID: $IGW_ID"
fi

# Asignamos un nombre para el IGW, reciblo el de la vpc pero concateno '-IGW'
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=${VPC_NAME}-IGW
# Conectamos el IGW con la VPC
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID


# ================================
# SECCION 4: Route Tables
echo "Iniciando creacion de Route Tables"
# Le decimos a aws que la route table corresponde a la VPC que creamos en este archivo ya
export RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
# comprobacion de errores, bueno, de NO errores (se me acaban las frases)
if [ -z "$RT_ID" ] || [ "$RT_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Route Table"
    exit 1

else
    echo "OK: Route Table creado con ID: $RT_ID"
fi
# Me vuelvo a aprovechar de VPC_NAME para nombrar cosas, ahora el route-table
aws ec2 create-tags --resources $RT_ID --tags Key=Name,Value=${VPC_NAME}-Public-RT
# Damos acceso global (0.0.0.0/0) al internetgateway
aws ec2 create-route --route-table-id $RT_ID \
    --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
# Conectamos dicho acceso global a nuestra subnet publica
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_A
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_B




# ================================
# SECCION 5: Security Group

# Creamos el security group y guardamos su id
# El SG es asignado a la VPC ya creada
echo "Iniciando creacion de segurity grup"
export SG_ID=$(aws ec2 create-security-group \
    --group-name lab2-security-group \
    --description "lab SG" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)
# comprobar
if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Security Group"
    exit 1
else
    echo "OK:Security Group creado con ID: $SG_ID"
fi
# Abrimos el puerto HTTP (80) al internet
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
# Comento la seccion de ssh, la justificacion? disminuir superficie de ataque
# Por que no lo borro entonces? Por si acaso xd
# aws ec2 authorize-security-group-ingress \
#     --group-id $SG_ID \
#     --protocol tcp \
#     --port 22 \
#     --cidr $(curl -s ifconfig.me)/32 
#
# ========================================
# SECCION 6: TARGET GROUP y ALB


# Crear Target Group
echo "Iniciando creacion de target group"
export TG_ARN=$(aws elbv2 create-target-group \
  --name web-tg \
  --protocol HTTP --port 80 \
  --target-type ip \
  --vpc-id $VPC_ID \
  --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)   

if [ -z "$TG_ARN" ] || [ "$TG_ARN" == "None" ]; then
    echo "ERROR: No se pudo crear el Target GROUP"
    exit 1
else
    echo "OK:Target group creado con ID: $TG_ARN"
fi
# Crear el ALB en subnets públicas
echo "Iniciando creacion de App load balancer"
export ALB_ARN=$(aws elbv2 create-load-balancer \
  --name web-alb \
  --subnets $SUBNET_PUB_A $SUBNET_PUB_B \
  --security-groups $SG_ID \
  --scheme internet-facing \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
    echo "ERROR: No se pudo crear el App Load Balancer"
    exit 1
else
    echo "OK:App Lad balancer creado con ID: $ALB_ARN"
fi

aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

aws elbv2 wait load-balancer-available --load-balancer-arn $ALB_ARN




# ==================
# SECCION 7: Imagen docker +ECR + IAM

echo "Creando Repositorio ECR: $REPO_NAME"
# Antes de pushear la imagen docker, creamos el repo ECR para poder alojarla
# Podria buildear la imagen antes de crear el repo, pero es mas organizado como lo tengo ahora
export ECR_URI=$(aws ecr create-repository \
    --repository-name $REPO_NAME \
    --image-scanning-configuration scanOnPush=true \
    --query 'repository.repositoryUri' \
    --output text)
if [ -z "$ECR_URI" ] || [ "$ECR_URI" == "None" ]; then
    echo "ERROR: No se pudo crear el repositorio ECR."
    exit 1
else
    echo "OK: Repositorio ECR listo. URI: $ECR_URI"
fi

echo "Accediendo a ECR"
aws ecr get-login-password --region $REGION \
  | docker login --username AWS \
  --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com

# Una vez creado el repo ECR creamos y pusheamos la imagen docker
echo "Creando la imagen docker"
# se elimina alguna POSIBLE imagen docker anterior
docker system prune -f 2>/dev/null 
docker rmi $APP:$SEMANTIC_VERSION 2>/dev/null || true
docker build --no-cache -t $APP:$SEMANTIC_VERSION sitio-web/
# Ejecutamos la imagen para pruebas locales
docker run --rm -d -p 8080:80 --name $APP $APP:$SEMANTIC_VERSION
echo "Esperamos 5 segundos"
sleep 5
curl -sf http://localhost:8080 && echo "OK: sitio responde localmente" || echo "ERROR: sitio no responde"
# mata el contenedor de prueba ANTES de seguir
docker kill $APP   

echo "Pusheando imagen docker"
# tageamos usando semantic version y pusheamos al ECR de AWS
docker tag $APP:$SEMANTIC_VERSION $ECR_URI:$SEMANTIC_VERSION
docker push $ECR_URI:$SEMANTIC_VERSION

cat > taskdef.json <<JSON
{ "family": "mi-web", "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "arn:aws:iam::${ACCOUNT}:role/ecsTaskExecutionRole",
  "containerDefinitions": [{ "name": "web",
    "image": "${ECR_URI}:${SEMANTIC_VERSION}",
    "portMappings": [{ "containerPort": 80 }] }] }
JSON




# ==================
# SECCION 8: CLUSTER + FARGATE

echo "Creando cluster $CLUSTER"
aws ecs create-cluster \
--cluster-name $CLUSTER \
--capacity-providers FARGATE \
--region $REGION

aws ecs register-task-definition --cli-input-json file://taskdef.json

aws ecs create-service \
  --cluster $CLUSTER --service-name $APP-svc \
  --task-definition mi-web --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration \
  "awsvpcConfiguration={subnets=[$SUBNET_PUB_A,$SUBNET_PUB_B],\
  securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers \
  "targetGroupArn=$TG_ARN,containerName=web,containerPort=80"

aws ecs wait services-stable \
    --cluster $CLUSTER \
    --services $APP-svc

aws ecs update-service \
--cluster $CLUSTER --service $APP-svc \
--desired-count 4

aws ecs wait services-stable \
    --cluster $CLUSTER \
    --services $APP-svc

echo "Creando DNS para acceder a paginas"
export DNS_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

sleep 10
echo "Veriicando http://${DNS_NAME}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${DNS_NAME})
if [ "$HTTP_CODE" = "200" ]; then
    echo "OK: Sitio responde con HTTP $HTTP_CODE en http://${DNS_NAME}"
else
    echo "ERROR: Sitio respondió con HTTP $HTTP_CODE (esperado 200)"
fi
# ========================================
# SECCION LIMPIEZA (CONFIRMAR ANTES)
# ========================================
echo ""
echo "===== LIMPIEZA DE RECURSOS ====="
read -p "¿Seguro que quieres eliminar todo? Revisa la GUI antes. Escribe 'si' para borrar: " CONFIRM
if [ "$CONFIRM" != "si" ]; then
    echo "Limpieza cancelada. Nada se borró."
    exit 0
fi

echo "Eliminando service..."
aws ecs update-service --cluster $CLUSTER --service $APP-svc --desired-count 0
echo "Esperando que las tareas se detengan"
aws ecs wait services-stable \
    --cluster $CLUSTER \
    --services $APP-svc
aws ecs delete-service --cluster $CLUSTER --service $APP-svc
aws ecs wait services-inactive \
    --cluster $CLUSTER \
    --services $APP-svc


echo "ELiminando repositorio ECR..."
aws ecr delete-repository --repository-name $REPO_NAME --force
sleep 1
echo "Eliminando cluster..."
aws ecs delete-cluster --cluster $CLUSTER
sleep 1

echo "Eliminando ALB..."
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
sleep 1
echo "Esperando eliminacion del ALB"
aws elbv2 wait load-balancers-deleted --load-balancer-arns $ALB_ARN
sleep 1

echo "Eliminando interfaces de red residuales..."
for eni in $(aws ec2 describe-network-interfaces \
    --filters Name=vpc-id,Values=$VPC_ID \
    --query 'NetworkInterfaces[?Status!=`available`].NetworkInterfaceId' \
    --output text); do
    aws ec2 delete-network-interface --network-interface-id $eni 2>/dev/null || true
done
sleep 10

echo "Eliminando Target Group..."
aws elbv2 delete-target-group --target-group-arn $TG_ARN
sleep 1

echo "Eliminando Security Group..."
aws ec2 delete-security-group --group-id $SG_ID
sleep 1

echo "Desasociando route tables..."
aws ec2 describe-route-tables --route-table-id $RT_ID \
    --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' \
    --output text | tr '\t' '\n' | while read assoc_id; do
    [ -n "$assoc_id" ] && aws ec2 disassociate-route-table --association-id "$assoc_id"
done
sleep 1
aws ec2 delete-route-table --route-table-id $RT_ID
sleep 1

echo "Desadjuntando y eliminando Internet Gateway..."
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
sleep 1
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
sleep 1

echo "Eliminando subnets..."
aws ec2 delete-subnet --subnet-id $SUBNET_PUB_A
sleep 1
aws ec2 delete-subnet --subnet-id $SUBNET_PUB_B
sleep 1

echo "Eliminando VPC..."
aws ec2 delete-vpc --vpc-id $VPC_ID

echo ""
echo "===== TODOS LOS RECURSOS ELIMINADOS ====="
