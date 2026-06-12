UNIVERSIDAD DE LOS LAGOS
Ingeniería Civil en Informática — Taller de Ingeniería Informática (FDICI12)

Laboratorio Práctico 2

Contenerización con Docker y despliegue en ECS / Fargate detrás de un balanceador

Resultado de aprendizaje

RA1 — Diseñar, desplegar y gestionar soluciones de software escalables y
resilientes en una plataforma de nube pública.

Unidad temática

Modalidad

Ponderación

Orquestación de contenedores: Amazon ECS, AWS Fargate e integración con
balanceador (Clase 8).

Grupo. Trabajo práctico con AWS CLI (laboratorio + trabajo autónomo).

15% de la nota final (corresponde al 25% del 60% de proceso).

Fecha de lanzamiento

Viernes 5 de junio (Clase 8).

Fecha de entrega

Instrumento

Viernes 12 de junio, hasta 23:59.

Rúbrica analítica de 4 niveles (ver sección 7).

1. Contexto y escenario de negocio

Acabas de incorporarte como ingeniero/a de plataforma a una startup chilena en crecimiento. Tú eliges el
rubro de tu emprendimiento: foodtech (al estilo NotCo), delivery (al estilo Cornershop), fintech, marketplace,
turismo del sur de Chile, etc. El nombre, la identidad y el contenido del sitio son tuyos: esta es tu plataforma.

Hoy, el MVP web del emprendimiento corre “a mano” en una sola instancia EC2 mediante un simple docker
run. El problema apareció el último viernes de promoción: un pico de tráfico tumbó el servidor y, además,
cada reinicio de la instancia deja el sitio caído hasta que alguien lo levanta. El negocio no puede seguir así.

Tu misión: contenerizar la aplicación y desplegarla de forma escalable y resiliente en Amazon ECS sobre
Fargate, detrás de un Application Load Balancer, usando exclusivamente la AWS CLI.

2. Objetivos de aprendizaje evaluados

•  Construir una imagen Docker reproducible de una aplicación web propia, aplicando buenas prácticas

(imagen base ligera, tag de versión explícito).

•  Publicar la imagen en un registro (Amazon ECR) y desplegarla en ECS sobre Fargate mediante una task

definition y un service.

•  Integrar el despliegue con la red (VPC, subredes en múltiples AZ, Security Groups) y un Application Load

Balancer, logrando alta disponibilidad.

•  Operar el servicio con AWS CLI de forma reproducible (variables de shell, script) y demostrar el escalado

declarativo.

•  Aplicar conciencia de costos: liberar todos los recursos al finalizar y justificar las decisiones de

dimensionamiento.

3. Requisitos técnicos (paso a paso, CLI-first)

Todo el aprovisionamiento debe hacerse con AWS CLI. La consola web solo se permite para verificación visual y
para capturar evidencia. Exporta variables de shell y reutilízalas para encadenar los comandos.

3.1 Contenerización de tu aplicación

1.  Crea una aplicación web mínima que represente tu emprendimiento (puede ser HTML estático servido

por Nginx, o una app simple en Node/Python que responda en un puerto HTTP).

Laboratorio Práctico 2 — Taller de Ingeniería Informática (FDICI12) — Universidad de Los Lagos   |   Página 1

2.  Escribe un Dockerfile con buenas prácticas: imagen base ligera y con tag de versión explícito (por

ejemplo nginx:1.27-alpine o python:3.12-slim), nunca “latest”.

3.  Construye y prueba la imagen localmente antes de subirla:
docker build -t mi-emprendimiento:1.0 .
docker run --rm -p 8080:80 mi-emprendimiento:1.0   # probar en http://localhost:8080

3.2 Publicación en Amazon ECR

Para que Fargate pueda ejecutar tu imagen, debe estar en un registro. Crea un repositorio en ECR,
autentícate, etiqueta y sube la imagen:

export AWS_REGION=us-east-1
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export REPO=mi-emprendimiento
aws ecr create-repository --repository-name $REPO --region $AWS_REGION
aws ecr get-login-password --region $AWS_REGION \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com
export IMG=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:1.0
docker tag mi-emprendimiento:1.0 $IMG && docker push $IMG

3.3 Red y balanceador (reutiliza lo de las Clases 4 y 6)

•  VPC con al menos dos subredes en dos zonas de disponibilidad distintas (alta disponibilidad).
•  Security Group que permita tráfico HTTP entrante (puerto 80).
•  Application Load Balancer con un target group de tipo IP (requerido para Fargate) y un listener en el

puerto 80.

3.4 Despliegue en ECS / Fargate

4.  Crea un cluster ECS con capacidad Fargate.
5.  Registra una task definition (networkMode awsvpc, CPU/memoria válidas para Fargate,

executionRoleArn, tu imagen de ECR y el puerto del contenedor).

6.  Crea un service con desired-count de al menos 2 tareas, launch type FARGATE, distribuido en las dos

subredes y asociado al target group del ALB.

aws ecs create-service --cluster $CLUSTER --service-name $APP-svc \
  --task-definition mi-emprendimiento --desired-count 2 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],\
   securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=web,containerPort=80"

3.5 Verificación y escalado

•  Accede al sitio por el DNS del ALB y confirma que responde tu aplicación.
•  Escala el service a 4 tareas y verifica que las nuevas tareas quedan registradas automáticamente en el

balanceador.

aws ecs update-service --cluster $CLUSTER --service $APP-svc --desired-count 4

3.6 Limpieza de recursos (obligatorio)

Libera TODO lo creado para evitar costos. Captura evidencia de la limpieza.

aws ecs update-service --cluster $CLUSTER --service $APP-svc --desired-count 0
aws ecs delete-service --cluster $CLUSTER --service $APP-svc --force
aws ecs delete-cluster --cluster $CLUSTER
# Elimina también ALB, target group y el repositorio ECR si los creaste para este lab.

4. Reglas y restricciones

Laboratorio Práctico 2 — Taller de Ingeniería Informática (FDICI12) — Universidad de Los Lagos   |   Página 2

•  AWS CLI obligatorio para todo el aprovisionamiento. La consola web solo para verificar y capturar

evidencia.

•  Tag de imagen explícito (de versión). El uso de “latest” se penaliza.
•  Despliegue en al menos dos zonas de disponibilidad (multi-AZ).
•  La sección de limpieza con evidencia es obligatoria: un trabajo sin limpieza no alcanza el nivel “Bueno”.
•  Trabajo individual. La detección de copia compromete la evaluación de los involucrados.

5. Entregables

7.  Informe técnico (PDF o DOCX, 4 a 8 páginas): identidad del emprendimiento, diagrama de la

arquitectura desplegada, decisiones técnicas justificadas (CPU/memoria, por qué Fargate), y una breve
reflexión de costos.

8.  Script reproducible (deploy.sh) con las variables exportadas y todos los comandos CLI usados, en orden.
9.  Dockerfile de la aplicación.
10. Evidencia (capturas): imagen visible en ECR; service con runningCount = 2; el sitio respondiendo en el

DNS del ALB; el service escalado a 4 tareas; y la evidencia de la limpieza final.

Laboratorio Práctico 2 — Taller de Ingeniería Informática (FDICI12) — Universidad de Los Lagos   |   Página 3

6. Rúbrica de evaluación (4 niveles)

Cada criterio se evalúa en cuatro niveles. El puntaje total se convierte a la escala 1,0–7,0 según la tabla de la
sección 6.1.

Criterio

Contenerización
(Dockerfile e imagen)

Publicación y despliegue
en ECS/Fargate

Red, multi-AZ e
integración con ALB

Uso de AWS CLI y
reproducibilidad

Limpieza y conciencia de
costos

Informe técnico y
justificación

%

20

25

20

15

10

10

Destacado / Bueno

Suficiente

Insuficiente

Dockerfile limpio, imagen base
ligera, tag de versión explícito;
imagen liviana y funcional.

Imagen funcional pero sin
optimizar o con tag poco claro.

No construye, o usa “latest”, o la
imagen no corre.

Imagen en ECR; task definition y
service correctos; tareas en
estado RUNNING vía CLI.

Despliega con ayuda; algún
parámetro subóptimo (CPU/RAM,
rol).

El service no levanta tareas sanas
o no usa Fargate.

VPC y 2+ subredes en 2 AZ; SG
correcto; sitio accesible por el
DNS del ALB.

Accesible pero en una sola AZ o
con SG demasiado permisivo.

El ALB no enruta tráfico a las
tareas.

Todo por CLI con variables
exportadas; script deploy.sh
reejecutable y ordenado.

Mayormente CLI, pero con valores
hardcodeados o pasos manuales
por consola.

Uso extensivo de la consola GUI o
sin script.

Elimina todos los recursos con
evidencia; justifica
dimensionamiento y costo.

Limpia lo principal pero deja
recursos menores activos.

Claro, con diagrama y decisiones
bien argumentadas; evidencia
completa.

Cumple lo mínimo;
argumentación o evidencia
parcial.

No hay evidencia de limpieza.

Incompleto o sin evidencia que
respalde el trabajo.

6.1 Conversión a escala de nota

Puntaje logrado (de 100)

Nota (escala 1,0 – 7,0, exigencia 60%)

100 – 90

89 – 75

74 – 60

59 – 40

39 – 0

6,4 – 7,0

5,5 – 6,3

4,0 – 5,4

2,5 – 3,9

1,0 – 2,4

7. Checklist de autoverificación (antes de entregar)

•  El Dockerfile usa una imagen base con tag de versión explícito (no “latest”).
•  La imagen fue construida, probada localmente y subida a Amazon ECR.
•  La task definition declara executionRoleArn, CPU/memoria válidas, networkMode awsvpc y el puerto del

contenedor.

•  El cluster usa Fargate y el service tiene desired-count ≥ 2 en dos zonas de disponibilidad.
•  El sitio responde correctamente por el DNS del ALB.
•  Se demostró el escalado a 4 tareas y su registro automático en el balanceador.
•  Todo el aprovisionamiento está en el script deploy.sh con variables exportadas.
•  Se eliminaron service, cluster, ALB, target group y repositorio ECR (con evidencia).
•  El informe incluye diagrama, justificación de decisiones y reflexión de costos.

Laboratorio Práctico 2 — Taller de Ingeniería Informática (FDICI12) — Universidad de Los Lagos   |   Página 4

8. Guía

8.1 Errores comunes y cómo abordarlos

•  executionRoleArn faltante: la task no puede descargar la imagen de ECR ni escribir logs. Verificar que

exista el rol ecsTaskExecutionRole con la política gestionada correspondiente.

•  Target group tipo “instance”: Fargate exige target group de tipo IP. Es el error de red más frecuente.
•  Sin login a ECR: el docker push falla con error de autorización. Repetir aws ecr get-login-password.
•  Security Group o assignPublicIp mal configurados: la tarea arranca pero el ALB no la alcanza o no

descarga la imagen. Revisar puerto 80 y salida a internet (subred pública o NAT).

•  Recursos sin liberar: recordar que ALB y NAT cobran por hora aunque no haya tareas. Pedir evidencia

explícita de limpieza.

8.2 Preguntas frecuentes

¿Puedo usar una imagen pública en vez de ECR?
No para el entregable principal: el objetivo es dominar el flujo build → push → deploy con tu propia imagen.
Puedes usar una imagen base pública dentro de tu Dockerfile.

¿Sirve cualquier app?
Sí, mientras exponga un puerto HTTP y represente tu emprendimiento. Mantenla simple; la dificultad está en
el despliegue, no en la app.

¿Fargate o EC2?
Fargate. El lab evalúa el modelo serverless de contenedores; EC2 como launch type queda fuera de alcance.

¿Qué CPU/memoria uso?
Lo mínimo válido (p. ej. 256 vCPU units / 512 MB) basta y se justifica por costo. Argumenta tu elección en el
informe.

¿Puedo reutilizar la VPC del laboratorio anterior?
Sí, siempre que tenga dos subredes en dos AZ y un SG que permita HTTP.

¿Qué pasa si no alcanzo a limpiar antes de la entrega?
Incluye igualmente los comandos de limpieza y ejecútalos; documenta con evidencia. Dejar recursos activos
afecta la nota y puede generar costos.

8.3 Recomendaciones de evaluación

•  Priorizar la evidencia funcional (sitio accesible por el ALB, tareas RUNNING) por sobre la prolijidad

estética del informe.

•  Valorar especialmente la reproducibilidad: un deploy.sh que un tercero podría reejecutar es señal de

dominio real.

•  Usar la rúbrica criterio por criterio; comentar al menos una fortaleza y una mejora por estudiante para

retroalimentación formativa.

8.5 Enlaces a documentación oficial

•  Amazon ECS — https://docs.aws.amazon.com/ecs/
•  AWS Fargate — https://docs.aws.amazon.com/AmazonECS/latest/userguide/AWS_Fargate.html
•  Amazon ECR — https://docs.aws.amazon.com/AmazonECR/latest/userguide/
•  Application Load Balancer con ECS —

https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-load-balancing.html

Laboratorio Práctico 2 — Taller de Ingeniería Informática (FDICI12) — Universidad de Los Lagos   |   Página 5

