# nexus_protocol

Los mensajes del canal teléfono ↔ Mac, y nada más: ni transporte, ni sockets, ni
lógica de negocio. Solo el contrato.

**Es un paquete y no una carpeta de la app por un motivo concreto**: lo usan los
dos lados. Si viviera dentro de la app de escritorio, el cliente móvil tendría que
copiarlo — y dos copias de un contrato son dos contratos que divergen.

Las decisiones que hay detrás de cada pieza están en
[`docs/PROTOCOL.md`](../../docs/PROTOCOL.md), que se escribió antes que esto. Si
algo aquí contradice ese documento, el documento gana y esto es un defecto.
