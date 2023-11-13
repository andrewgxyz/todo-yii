<?php

return [
  'class' => 'yii\db\Connection',
  'dsn' => 'mysql:host=' . getenv('DB_PORT') . ';dbname=todoyii' . getenv('DB_DATABASE'),
  'username' => getenv('DB_USERNAME'),
  'password' => getenv('DB_PASSWORD'),
  'charset' => 'utf8',

  // Schema cache options (for production environment)
  //'enableSchemaCache' => true,
  //'schemaCacheDuration' => 60,
  //'schemaCache' => 'cache',
];
