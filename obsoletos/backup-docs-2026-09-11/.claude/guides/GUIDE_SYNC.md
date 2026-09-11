# GUIDE_SYNC — Sincronización erp-app ↔ erp-cliente

## Fuente de verdad

erp-app = autoridad

erp-cliente = consumidor

La autoridad siempre es unidireccional.

---

## Requisitos obligatorios

Toda sincronización debe soportar:

- idempotencia
- versionado
- auditoría
- validación estructural
- validación de negocio

---

## Versionado

Toda entidad sincronizable debe utilizar una versión monotónica entera.

```
version = 1
version = 2
version = 3
```

No utilizar timestamps para resolver conflictos.

---

## Resolución de conflictos

La autoridad siempre gana.

No realizar merge automático.

No introducir CRDT.

No implementar mecanismos complejos sin necesidad demostrada.

---

## Contrato de respuesta ante conflictos

Cuando una operación sea rechazada por conflicto de versión:

- retornar conflicto
- incluir la versión actual del registro
- incluir el estado actual autorizado por el servidor
- no realizar merge automático

```json
{
  "resultado": "conflicto",
  "versionActual": 12,
  "registroActual": {}
}
```

El cliente debe re-sincronizar utilizando la versión provista por la autoridad.
