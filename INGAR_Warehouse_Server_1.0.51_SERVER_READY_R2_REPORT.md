# INGAR Warehouse Server Edition 1.0.51 — R2

## Defecto físico encontrado en Codespaces
El self-test llegó a SQLite, abrió la DB y levantó el servidor, pero falló en:

`Una DB nueva debe requerir configuración inicial`

La DB nueva tenía schema 053 pero el Server Edition no había ejecutado el mismo
bootstrap `ensureInitialAccess()` que el flujo Windows ejecuta antes del primer acceso.

Además, al fallar la aserción, el self-test podía dejar el listener temporal activo
en un puerto aleatorio (en la prueba se observó 33969).

## Corrección R2
- `scripts/server-self-test.js`
  - ejecuta `ensureInitialAccess(temp)` antes de arrancar el servidor;
  - siempre ejecuta `stopServer()` en `finally`.
- `scripts/start-server.js`
  - ejecuta `ensureInitialAccess(IWC_DATA_DIR)` antes de servir tráfico real.
- `SETUP_INGAR_SERVER_READY_R2.sh`
  - elimina cualquier self-test anterior huérfano;
  - detiene un runtime previo antes de reemplazar código;
  - preserva DB y secreto fuera de la carpeta de aplicación.

## Invariantes
- schema máximo 053;
- migración 054 ausente;
- no cambia DB funcional ni APIs;
- no agrega fixtures/mocks;
- primer Administrador sigue siendo self-setup real.

## QA estático
- JavaScript syntax: PASS
- Payload SHA-256: `2c66411ae57b519fbc14823936c0b5b19ee4d86e3d775710a31794268aebe232`

## Comando de instalación
```bash
chmod +x SETUP_INGAR_SERVER_READY_R2.sh
./SETUP_INGAR_SERVER_READY_R2.sh
```

Resultado esperado:
`SERVER SELFTEST PASS`
seguido de:
`INGAR Warehouse ACTIVO en puerto 4317`
y:
`SERVER READY R2`
