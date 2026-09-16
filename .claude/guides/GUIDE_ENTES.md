# GUIDE_ENTES — Entes, estados, relaciones, acciones y eventos

Cómo se describe un módulo para que otro módulo lo pueda usar sin conocerlo. Se carga en el paso 0 de
`GUIDE_MODULO_NUEVO.md` y al tocar cualquier cosa que cruce módulos: `entes`, chips, "Relacionar",
disparadores, compartir al asignar.

Módulo de referencia: **obras** (`db_schema/obras.md`, `decisiones/obras/visibilidad.md`). Todo lo que
esta guía pide ya está construido ahí una vez; se copia la forma, no se reinventa. Las funciones
genéricas viven en `db_schema/core.md` (`sql/059`–`062`).

## Vocabulario

| Término | Qué es | Cómo se implementa |
|---|---|---|
| **Ente** | Un registro con ficha propia, sujeto de relaciones. Ej: obra, empresa, persona | Tabla `{modulo}_{ente}` + fila en `entes` + entrada en `ENTES` (`lib/entes.ts`) |
| **Estado** | Un enum en una sola columna: el ente está en exactamente un estado | `CREATE TYPE estado_{ente} AS ENUM`, columna `estado`, `entes.estados` |
| **Propiedad** | Un dato del ente. Escalar (columna) o relacional: otro ente con un rol ("la obra tiene desarrollador") | Columna · fila en la tabla puente con `roles` |
| **Relación** | Vínculo entre dos entes, con rol, sin autoridad propia | Tabla puente `{modulo}_{ente_a}_{ente_b}` con `roles enum[]`, `creado_por`, `activo` |
| **Acción** | Lo que un usuario hace sobre un ente | Submódulo-función + policy o función SQL (`GUIDE_PERMISSIONS.md`) |
| **Evento** | Algo que le pasó a un ente y otro módulo puede escuchar | Fila en `eventos`, emitida por los triggers del módulo (§2.8) |

No son entes: configuración (plantillas), logs, tablas puente, preferencias (`usuario_*`). Un ente
tiene ficha, dueño, y puede aparecer como chip en otro módulo.

## 1. La ficha del módulo — antes de escribir SQL

Junto con el árbol de vistas y funciones (`GUIDE_MODULO_NUEVO.md`, paso 0), se lista y se aprueba con
el usuario. Un módulo puede no tener entes (el dashboard, un módulo de reportes o de configuración):
la ficha dice `Entes: ninguno` y entonces tampoco emite eventos. Sin ficha aprobada no hay SQL.

```
Módulo: obras
Entes
├── obra      — dueño responsable_id · estado estado_obra · datos {nombre} · ruta /obras/{id} · submódulo obras_ver
├── empresa   — dueño creado_por · sin estado · ruta /obras/empresas/{id} · submódulo obras_empresas
└── persona   — dueño creado_por · sin estado · ruta /obras/personas/{id} · submódulo obras_personas · contacto solo por función
Relaciones
├── obra ↔ empresa    — rol_empresa[]            (obras_obra_empresa)
├── obra ↔ persona    — rol_persona[] + empresa  (obras_obra_persona)
├── persona ↔ empresa — cargo                    (obras_persona_empresa)
└── obra ↔ persona    — referente + comisión     (obras_obra_referente)
Acciones
├── obra: crear · editar · cambiar estado · vincular · marcar referente · transferir · compartir · desactivar · reactivar · aprobar alta
├── empresa: crear · editar · vincular · transferir · compartir · desactivar · aprobar alta
└── persona: crear · editar · vincular · transferir · compartir · desactivar · aprobar alta · ver contacto (registra el acceso)
Eventos que emite (sql/068)
├── obra: alta · estado · relacion_alta · relacion_baja (empresa, persona) — disparan
├── obra: baja · reactivacion — solo log: pasan por obras_set_activo (DEFINER)
└── empresa, persona: ninguno
Eventos que consume
└── ninguno
```

Un módulo puede emitir y consumir (Tareas), emitir sin consumir (Obras), o no tener entes ni
eventos. `transferencia`, `compartido` y `revocado` todavía no los emite nadie: Obras los registra en
`obras_transferencias` y en las tablas `*_compartida`, y entran al enum con su primer emisor (§2.8).

## 2. Contrato de un ente

Todo ente cumple esto en su migración. Los nombres siguen a Obras.

### 2.1 Tabla

Además de las columnas de `GUIDE_DB.md` (`id`, `activo`, `created_at`, `updated_at`):

- **Dueño**: `creado_por` — o `responsable_id` si puede cambiar por transferencia — uuid FK → `usuarios`
  NOT NULL, fuera del `GRANT UPDATE`: cambia solo por función.
- **Estado**, si lo tiene: una sola columna `estado` de un enum propio. Nunca dos columnas de estado,
  nunca texto. Un estado derivado ("bloqueada") no se guarda, se calcula.
- **Dato sensible** (contacto): fuera del `GRANT SELECT`; se lee por una función DEFINER que registra el
  acceso (`obras_ficha_persona`).
- **RLS por dueño**: SELECT = dueño, o grant activo, o permiso `_todas`. El dueño se prueba como
  columna (`creado_por = auth.uid()`), no dentro de una función que relea la fila (`GUIDE_DB.md`, trampa
  `INSERT … RETURNING`).

### 2.2 Registro en `entes`

```sql
INSERT INTO entes (codigo, modulo, submodulo, estados, datos, ruta, tabla, disparos)
VALUES ('presupuesto', 'presupuestos', 'presupuestos_ver', 'estado_presupuesto', '{numero}', '/presupuestos/{id}',
        'presupuestos', '{alta,estado}')
ON CONFLICT (codigo) DO NOTHING;
```

- `codigo` singular, sin prefijo de módulo, único para siempre: es destino de FK.
- `submodulo`: la vista que abre la ficha. Sin ella el ente no existe para ese usuario (RLS de `entes`).
- `estados` NULL si no tiene. `datos`: columnas citables como `{columna}` desde otro módulo — nunca contacto.
- `tabla`: de donde un consumidor lee la fila. `disparos`: los eventos que pueden disparar una plantilla —
  solo los que ocurren como quien actúa (uno que pasa por una función DEFINER no dispara), y ninguno si
  una plantilla disparada por el ente crearía otro igual (la tarea).
- `ruta`: la ficha, con `{id}`. Tiene que abrir sin más contexto que el id.

Y en `ENTES` (`lib/entes.ts`): `nombre`, `un`, `el`, labels de `estados` y `roles`, `datos` con label y
ejemplo. La base sabe qué entes hay; la UI sabe cómo se dicen. El módulo re-exporta los labels
(`LABEL_ESTADO` en `modules/obras/types.ts`), nunca tiene un segundo mapa.

### 2.3 Las siete funciones cross-módulo — sumar la rama, no tocar las demás

Cada una ramifica por `entes.modulo` (`CASE` / `IF`) y delega en una función del módulo:

| Genérica (core) | Rama del módulo | Contesta |
|---|---|---|
| `etiqueta_registro(ente, id)` — INVOKER | `{modulo}_etiqueta(tipo, id)` — INVOKER | El nombre si quien pregunta lo ve, NULL si no. **Es la definición de "lo ve"** |
| `puede_abrir_registro(ente, id, usuario)` — DEFINER | `{modulo}_puede_abrir(tipo, id, usuario)` | Lo mismo, por usuario explícito, sin grants contextuales |
| `puede_compartir_registro(ente, id, usuario)` — DEFINER | `{modulo}_puede_compartir(tipo, id)` | Si quien llama (el dueño) puede dárselo a `usuario` |
| `compartir_registros(selecciones)` — INVOKER | `{modulo}_compartir_registros(usuario, registros)` | Comparte. **Aditivo**: nunca revoca ni reordena cascadas |
| `buscar_registros(modulo, texto)` — INVOKER | `{modulo}_buscar(texto)` | Lo que quien busca puede abrir, con `href` |
| `relacionados_de_registro(ente, id)` — INVOKER | `{modulo}_relacionados_{ente}(id)` | `(ente, registro_id, rol)`: las propiedades relacionales |
| `puede_ver_relacion(ente, id, ente_rel, id_rel)` — INVOKER | `{modulo}_puede_ver_relacion(tipo, id, ente_rel, id_rel)` | Si quien pregunta ve algún vínculo del par, activo o no: un EXISTS sobre la puente, que decide su RLS. Lo pide la RLS de `eventos` |

La visibilidad por usuario explícito se escribe una vez: `{modulo}_puede_ver_{ente}_de(id, usuario)` es
el cuerpo; `{modulo}_puede_ver_{ente}(id)` es un envoltorio de una línea con `auth.uid()` que usan
las policies (`sql/062`). Las del módulo que llama una genérica DEFINER van sin GRANT; las que llama una
INVOKER (`etiqueta_registro`, `relacionados_de_registro`, `puede_ver_relacion`) lo necesitan. Si la regla depende de
columnas de la propia fila (Tareas: hilo, visibilidad, proyecto), la `_de` recibe esas columnas y no el
id: en un UPDATE la policy de SELECT se evalúa sobre la fila nueva, y releer la tabla daría la vieja
(`tareas_puede_ver_tarea_de`, `sql/067`).

### 2.4 Privacidad y compartir

- **Todo ente nace privado.** Nada se ve por estar vinculado, por haberlo creado otro ni por tener el
  módulo. Se amplía solo por acto explícito — compartir, transferir, asignar, membresía — o por un
  permiso `_todas`, que es la excepción administrativa. Quién es el dueño de la visibilidad lo define
  el módulo: en Obras el `responsable_id`; en Tareas los asignados (`sql/013`).
- **Compartir es por ente y la cascada es explícita.** Tabla `{modulo}_{ente}_compartida (ente_id,
  usuario_id, otorgada_por, activo, origen_*)`, UNIQUE entero por par (re-compartir revive). Compartir
  un padre ofrece un checklist de lo relacionado; lo tildado recibe su propio grant con
  `origen_{padre}_id`; revocar el padre apaga solo esos. Compartir la obra no comparte los contactos.
- **Lectura, no edición.** El receptor ve; edita el dueño. Un grant recibido no se re-comparte.
- **"No existe" antes que "sin permiso".** Un chip de lo que no ves no se dibuja; una ficha que no ves
  da `notFound()`; la búsqueda no lo devuelve; el aviso queda sin nombre. `etiqueta_registro` NULL es
  el único `if()`. La excepción registrada es `sin_acceso` (`decisiones/obras/visibilidad.md`).
- **Quien recibe algo que apunta a lo que no ve** (una tarea con una obra): lo decide la base con
  `queda_afuera` y la UI pregunta antes con `useConfirmarAcceso`
  (`components/ui/CompartirAccesoPanel.tsx`) sobre `lib/accesos.ts`. Se reutilizan, no se copian.

### 2.5 Estados

- Enum propio, un valor por fila. Las invariantes de transición van en CHECK o trigger
  (`obras_perdida_con_motivo`), no en TypeScript.
- Cambiar de estado es una acción (policy de UPDATE o función) y siempre queda auditada: quién, qué,
  cuándo, valor anterior (§2.8).
- El módulo avisa con un trigger de una línea sobre la tabla y no decide nada más:
  `AFTER INSERT OR UPDATE OF activo, estado … EXECUTE FUNCTION emitir_eventos_registro('<ente>')`.
  Qué pasa lo decide quien escucha.
- Ensayar un cambio antes de guardarlo (`obras_ensayar_estado`): UPDATE real dentro de un bloque que se
  revierte solo, INVOKER. Solo si la UI necesita preguntar antes.

### 2.6 Relaciones

- Puente `{modulo}_{ente_a}_{ente_b}` con `roles enum[]` (una relación con dos roles, no dos relaciones),
  `CHECK cardinality(roles) > 0`, `creado_por` por trigger `set_creado_por`, unique parcial por par
  `WHERE activo`. Ser algo por tener una fila (referente) no se duplica como rol.
- Con un ente de **otro módulo**: si es siempre el mismo ente, FK directa (`presupuestos.obra_id →
  obras`); si es "cualquier ente", el par `(ente text FK → entes, registro_id uuid sin FK)` como
  `tareas_vinculos`, y la policy de INSERT exige `etiqueta_registro(ente, registro_id) IS NOT NULL`.
- La relación se expone por `{modulo}_relacionados_{ente}` para que otro módulo pida "el arquitecto de
  esta obra" sin conocer la tabla.
- Y avisa con otro trigger de una línea sobre el puente: `AFTER INSERT OR UPDATE OF activo, roles …
  EXECUTE FUNCTION emitir_eventos_relacion('<ente>', '<columna>', '<ente relacionado>', '<columna>')`.

### 2.7 Acciones

- Una acción = un submódulo-función `{modulo}_{slug}` + su regla en Postgres: policy, o función `.rpc()`
  con `tiene_permiso` en la primera línea y `RAISE … USING ERRCODE = '{XX}NNN'` (clase propia por módulo:
  `OB`, `TA`). `actions.ts` es glue.
- Acción sobre un ente de **otro** módulo ("sacar presupuesto de la obra"): vive en el módulo que la
  ofrece, se relaciona por FK o `(ente, registro_id)`, y se muestra en la ficha ajena **por composición
  en `app/`**: la page de la ficha importa el componente y lo pasa como prop (`seccionTareas` en
  `obras/[id]/page.tsx`). Los módulos no se importan entre sí.

### 2.8 Eventos

Vocabulario, enum `tipo_evento`:

| Evento | Cuándo | `detalle` |
|---|---|---|
| `alta` | INSERT de un ente activo | — |
| `baja` / `reactivacion` | `activo` true → false / false → true | — |
| `estado` | la columna de estado cambia de verdad, o nace con valor | `{estado, anterior}` |
| `relacion_alta` / `relacion_baja` | otro ente se vincula / desvincula con un rol (uno por rol) | `{ente, registro_id, rol}` |
| `transferencia` | cambia el dueño | `{de, a}` |
| `compartido` / `revocado` | grant otorgado / apagado | `{usuario_id}` |

Editar una columna escalar no es evento: sin consumidor es ruido y `updated_at` ya lo dice. Si aparece
un caso, se suma `dato` con `{columna}`.

Construido en `sql/068` (`db_schema/core.md`):

- Tabla cross-módulo `eventos (ente, registro_id, evento tipo_evento, detalle jsonb, actor_id,
  created_at)`, append-only y sin `activo` (una auditoría no oculta sus filas). RLS SELECT:
  `etiqueta_registro(ente, registro_id) IS NOT NULL`, y para `relacion_*` además `puede_ver_relacion`
  (`sql/069`): ver la obra no es ver todos sus vínculos. INSERT solo por
  `emitir_evento(ente, registro_id, evento, detalle)`, **INVOKER** con policy `pg_trigger_depth() > 0`
  (el truco de `tareas_vinculos`): con DEFINER los consumidores correrían como `postgres` y
  `disparar_plantillas` no dispararía.
- Cada módulo emite desde **sus** triggers, con las dos funciones genéricas: `emitir_eventos_registro`
  sobre el ente (alta, baja, reactivación, estado) y `emitir_eventos_relacion` por tabla puente (un
  evento por rol que aparece o se va, del lado del primer ente). Nunca desde `actions.ts`.
- Los consumidores cuelgan de `AFTER INSERT ON eventos` y filtran por `(ente, evento)`. Hoy uno:
  `disparar_plantillas`, con `disparo_evento` (y `disparo_estado` o `disparo_rol`) en la plantilla;
  lee la fila de `entes.tabla` con la RLS de quien actuó.
- Es también la auditoría que `GUIDE_DB.md` exige (`tareas_eventos` se mudó ahí). Un log propio que ya
  existe (`obras_transferencias`) sigue valiendo: no se escribe en los dos. `transferencia`,
  `compartido` y `revocado` se suman al enum con su primer emisor.

## 3. UI de un ente

- **Ficha**: la ruta de `entes.ruta`; su `page.tsx` da `notFound()` sin la vista o sin la fila.
- **Chip**: `VinculosChips` (`modules/tareas/components`; sube a `components/ui/` con el segundo módulo
  que lo use). `ENTES[ente].nombre` + etiqueta, link a `href`. Sin etiqueta no se renderiza.
- **Elegir un ente de otro módulo**: `RelacionarRegistro` — módulo primero, después el buscador
  (`buscar_registros`). Misma subida a `components/ui/`.
- **Sección de otro módulo en la ficha**: composición en `app/` (§2.7).
- **Texto que menciona un ente** (descripción, plantilla): se guarda la referencia, no el nombre —
  `{ente:uuid}` en el texto, resuelto al mostrar con `etiqueta_registro`: link si lo ve, nada si no.
  Igual que las notificaciones: *apuntan, no copian*. Los `{dato}` de plantillas son la excepción por
  diseño (se copian para quien no ve el registro) y por eso nunca llevan contacto.
- **Arrastrar**: el chip es la unidad de arrastre cuando exista. Hoy es clic — sin librería de dnd, y
  el arrastre nativo no anda en touch (`decisiones/tareas/plantillas.md`). Sumar una es "sin librerías
  nuevas sin consultar".

## Checklist por ente

- [ ] Tabla con dueño fuera del `GRANT UPDATE`; RLS por dueño probada como columna
- [ ] Fila en `entes` + entrada en `ENTES` con labels de estados y roles
- [ ] Rama en `etiqueta_registro`, `puede_abrir_registro`, `puede_compartir_registro`,
      `compartir_registros`, `buscar_registros` y, con relaciones, `relacionados_de_registro` y
      `puede_ver_relacion`
- [ ] `{modulo}_puede_ver_{ente}_de(id, usuario)` + envoltorio con `auth.uid()`
- [ ] Tabla `_compartida` con `origen_*`, funciones compartir / revocar, checklist de cascada
- [ ] Estado: enum, CHECKs de transición
- [ ] Eventos: `emitir_eventos_registro` sobre la tabla, `emitir_eventos_relacion` por puente, `tabla` y
      `disparos` en `entes`
- [ ] Relaciones: puente con `roles[]`, `creado_por` por trigger, `{modulo}_relacionados_{ente}`
- [ ] Eventos que emite y que consume, listados en la ficha del módulo
- [ ] Ficha en `entes.ruta`; chips y buscador reutilizados, no copiados
- [ ] `db_schema/core.md` (fila de `entes`, rama en cada función) y `db_schema/<modulo>.md`
- [ ] Test de RLS con dos usuarios y `ROLLBACK` (`sql/tests/`), apagando los permisos reales antes de
      prender los del test
