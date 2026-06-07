#!/bin/bash

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
# =================================
# SECCION 1: CREACION VPC
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



# ================================
# SECCION 2: CREAR SUBNET
# ================================
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
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
# Conectamos dicho acceso global a nuestra subnet publica
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_A
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB_B




# ================================
# SECCION 5: Security Group

# Creamos el security group y guardamos su id
# Le ponemos un nombre, como curiosidad al principio lo llame 'sg-lab', amazon da error automatico con eso
# El SG es asignado a la VPC ya creada
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
# Dejamos el puerto ssh (22) disponible unicamente para nuestra Ip personal
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr $(curl -s ifconfig.me)/32 


# ========================================
# SECCION 6: TARGET GROUP y ALB


# Crear Target Group
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
    echo "OK:Security Group creado con ID: $TG_ARN"
fi
# Crear el ALB en subnets públicas
export ALB_ARN=$(aws elbv2 create-load-balancer \
  --name web-alb \
  --subnets $SUBNET_PUB_A $SUBNET_PUB_B \
  --security-groups $SG_ID \
  --scheme internet-facing \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
if [ -z "$ALB" ] || [ "$ALB" == "None" ]; then
    echo "ERROR: No se pudo crear el App Load Balancer"
    exit 1
else
    echo "OK:Security Group creado con ID: $ALB"
fi


aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN




# ==================
# SECCION 7: CLUSTER + FARGATE
#
#
aws ecs create-cluster \
--cluster-name $CLUSTER \
--capacity-providers FARGATE \
--region $REGION
cat > taskdef.json <<'JSON'
{ "family": "mi-web", "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "arn:aws:iam::<ACCOUNT>:role/ecsTaskExecutionRole",
  "containerDefinitions": [{ "name": "web",
    "image": "nginx:1.27",
    "portMappings": [{ "containerPort": 80 }] }] }
JSON
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

aws ecs update-service \
--cluster $CLUSTER --service $APP-svc \
--desired-count 4
