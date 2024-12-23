### NestJs Notes todo app

#### Infrastructure

![Infrastructure](/terraform/infrastructure.jpg)

A tutorial on how to create a simple nestjs application, creating e2e endpoints and documenting the APIs

.env variable

```
DATABASE_URL =
PORT = 80
```

### Set up:

-    git clone
-    npm install
-    npm run start:dev
-    npm run test:e2e

### Run using docker-compose

-    `git clone`
-    `docker-compose up`

### API Docs

`http://localhost:3000/api/`

### Terraform

> set DATABASE_URL durring apply

```sh
  terraform apply -var "DATABASE_URL=databse.url"
```

### Blog Posts

-    On how to create API endpoints: https://techshrimps.hashnode.dev/get-started-with-nestjs-and-create-a-todo-notes-app-ck9pni8xv02sohjs1f66yuqm5
-    On how to create e2e tests for the endpoints: https://techshrimps.hashnode.dev/get-started-with-nestjs-and-create-a-todo-notes-app-creating-e2e-tests-part-2-ck9vxmjj500tgnbs18l79ztcm
-    On how to document the API endpoints using @nestjs/swagger: https://techshrimps.hashnode.dev/get-started-with-nestjs-and-create-a-todo-notes-app-documenting-the-api-endpoints-with-nestjs-swagger-part-3-ck9y0znek028no9s1tv98v1s7
