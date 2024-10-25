import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { AppModule } from './app.module';
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";
import * as dotenv from "dotenv";
import { NoteModule } from "../src/modules/note.module";


dotenv.config();

const PORT = process.env.PORT || 3000;

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix("api/v1");

  const options = new DocumentBuilder()
    .setTitle("Notes todo app")
    .setDescription(
      "A documentation for notes"
    )
    .setVersion("1.0")
    .addTag("Notes")
    .build();
  const appDocument = SwaggerModule.createDocument(app, options, {
    include: [NoteModule]
  });
  SwaggerModule.setup("api", app, appDocument);
  await app.listen(PORT);

  const logger = new Logger('bootstrap');

  logger.log(`Listening on ${await app.getUrl()}`);
  logger.log(`Log to test autodeploy`);
}
bootstrap();
