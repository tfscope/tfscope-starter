# .env.example
#
# preencher com terraform output
# NUNCA commitar .env no git

# app - django
# terraform output -raw app_pool_uri (modulo db-postgres)
APP_POOL_URI=postgresql://user:pass@private-host:port/dbname?sslmode=require

# valkey - cache + filas
# terraform output -raw uri (modulo db-valkey)
VALKEY_URI=valkeys://default:pass@private-host:port

# keycloak - auth
# converter terraform output keycloak_pool_uri pra formato JDBC:
#   postgresql://user:pass@host:port/db  -->  jdbc:postgresql://host:port/db?user=user&password=pass&sslmode=require
KEYCLOAK_JDBC_URI=jdbc:postgresql://private-host:port/dbname?user=user&password=pass&sslmode=require
KEYCLOAK_HOSTNAME=auth.empresamais.com.br
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=trocar-em-producao

# app image
APP_IMAGE=registry/app:latest