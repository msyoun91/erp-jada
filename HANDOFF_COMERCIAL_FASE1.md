# TRASPASO — Módulo Comercial, Fase 1

Documento de continuidad. Se escribe durante la Fase 1 para que, al cerrarla,
`/clear` no pierda contexto: quien retome lee esto y `decisiones/comercial.md`
y no necesita la conversación original.

Spec de origen: "Módulo de Prospectos y Red Comercial — Fase 1" (pegada por el
usuario, no versionada). Lo que sigue es la spec **corregida** contra el código
real — donde difieren, manda este documento.

---

## 1. Qué es Fase 1

Base de datos comercial: registrar, relacionar y volver a encontrar obras,
empresas, personas y la lectura comercial de cada obra (prospecto).

**Fuera de alcance, explícito:** tareas, actividades, agenda, recordatorios,
emails, automatizaciones, pipeline, forecast, presupuestos, cotizaciones,
contratos, liquidación de comisiones, instalación, postventa.

La comisión que se guarda acá es **configurativa**. No dispara cálculo
financiero de ningún tipo.

---

## 2. Decisiones cerradas (con el usuario, antes de escribir SQL)

| # | Decisión | Elegido |
|---|---|---|
| 1 | Visibilidad de prospectos | **Por responsable comercial** + función admin `comercial_gestionar_ajenos` |
| 2 | Quién ve el % de comisión | **Función propia** `comercial_comision` |
| 3 | Roles múltiples empresa/persona en una obra | **Array de enum** (`rol_empresa[]` / `rol_persona[]`) |
| 4 | Referentes por obra | **Uno solo** — unique parcial `(obra_id) WHERE es_referente AND activo` |
| 5 | Estados/tipos/roles | **Enums** (los agrega dev en migración). Solo `comercial_fuentes` es tabla catálogo |

### Correcciones a la spec original

- **`rol` singular → `roles` array.** La spec definía columna `rol` y a la vez
  exigía roles múltiples (§10, §16, §17). Manda el array.
- **`tiene_comision` no existe.** Dos columnas para un dato es duplicación. La
  comisión vive en `comercial_comisiones`: hay fila = hay comisión. RN-09 pasa
  a ser estructuralmente imposible de violar, no una validación.
- **`referente` sale del enum `rol_persona`.** Es la columna `es_referente`
  (la que lleva el unique). Tenerlo en los dos lados era doble fuente.
- **`fecha_estimada_compra` solo en el prospecto.** La spec la repetía en obra
  y en prospecto.
- **`empresa_principal` de la tabla de listado no es columna.** Se deriva por
  prioridad de rol (desarrolladora > constructora > inmobiliaria) en la vista
  SQL. Columna propia se desincroniza con `obra_empresa`.
- **Detección de duplicados:** constraint duro solo donde el dato identifica
  (CUIT, email). Para obras, aviso blando en el formulario — sin motor de
  matching, sin `pg_trgm`.

---

## 3. Naming de tablas — excepción al prefijo por módulo

`GUIDE_DB.md` pide prefijo `{modulo}_{entidad}`. Acá se aplica solo a lo que es
comercial de verdad:

| Sin prefijo (infra de negocio, cross-módulo) | Con prefijo (comercial) |
|---|---|
| `empresas`, `personas`, `obras`, `obra_empresa`, `obra_persona` | `comercial_prospectos`, `comercial_fuentes`, `comercial_comisiones` |

Motivo: la obra sobrevive al prospecto — Presupuestos, Instalación y Postventa
van a colgar de `obras`, no de comercial. Empresas y personas las va a usar
Clientes. Prefijarlas hoy obliga a renombrarlas mañana.

---

## 4. Permisos — árbol aprobado

```
Módulo: Comercial   (modulo = 'comercial')
├── comercial_prospectos (vista)
│   ├── comercial_prospectos_gestionar (funcion)
│   ├── comercial_gestionar_ajenos (funcion)
│   └── comercial_comision (funcion)
├── comercial_obras (vista)
│   └── comercial_obras_gestionar (funcion)
├── comercial_empresas (vista)
│   └── comercial_empresas_gestionar (funcion)
└── comercial_personas (vista)
    └── comercial_personas_gestionar (funcion)
```

`comercial_gestionar_ajenos` es el eje admin: ver prospectos de otros, editarlos
y traspasar el responsable. Sin él, cada uno ve y toca los suyos.

`comercial_comision` gatea la tabla `comercial_comisiones` entera vía RLS. Quien
no la tiene no ve el porcentaje **ni sabe que existe una comisión** — la fila no
entra en su SELECT. Es deliberado: gatear una columna requeriría vista +
grants por columna + trigger; gatear una fila lo resuelve la RLS que ya existe.

---

## 5. Estado — Fase 1 cerrada

- [x] SQL (`sql/018_comercial.sql`) escrito
- [x] SQL corrido en Supabase — migraciones `comercial_fase1` y `comercial_fase1_funciones`
- [x] `database.types.ts` actualizado (a mano: el CLI necesita `SUPABASE_ACCESS_TOKEN`, ver §6)
- [x] `db_schema.md` sincronizado
- [x] `types.ts` · `permissions.ts` · `queries.ts` · `actions.ts`
- [x] UI — Prospectos (listado + ficha), Obras (listado + ficha + relaciones), Empresas, Personas
- [x] Sidebar + layout del módulo (`/comercial`, `/comercial/obras`, `/comercial/empresas`, `/comercial/personas`)
- [x] `decisiones/comercial.md` actualizado
- [x] `npx tsc --noEmit` limpio · `npx eslint src` sin errores nuevos · `next build` OK

### Archivos del módulo

```
sql/018_comercial.sql
erp-app/src/lib/usuarios.ts              # getUsuarioActualId / getUsuariosActivos (salieron de tareas)
erp-app/src/modules/comercial/
├── types.ts · permissions.ts · queries.ts · actions.ts
└── components/
    ├── comercialLabels.ts               # etiquetas de enums + empresaPrincipal/referente derivados
    ├── AvisoDuplicados.tsx · Dato.tsx · RolesPicker.tsx
    ├── ProspectosView.tsx · ProspectoFormPanel.tsx · ProspectoDetailPanel.tsx
    ├── ObrasView.tsx · ObraFormPanel.tsx · ObraDetailPanel.tsx · ObraRelaciones.tsx
    ├── RelacionEmpresaPanel.tsx · RelacionPersonaPanel.tsx
    ├── EmpresasView.tsx · EmpresaFormPanel.tsx
    └── PersonasView.tsx · PersonaFormPanel.tsx
erp-app/src/app/(erp-app)/comercial/{layout,page}.tsx + obras/ empresas/ personas/
```

### Antes de usarlo

**Nadie tiene los permisos todavía.** Los 10 submódulos están sembrados pero sin
asignar: entrar a `/usuarios` → Permisos y darse `comercial_prospectos`,
`comercial_obras`, `comercial_empresas`, `comercial_personas` más sus funciones.
Sin ninguna vista, `/comercial` devuelve 404 y el módulo no aparece en el nav —
es el comportamiento correcto, no un bug.

Flujo de carga: **Empresas y Personas → Obras (y ahí se relacionan) → Prospecto.**
El prospecto solo elige una obra ya cargada.

---

## 6. Pendiente conocido (no bloquea el cierre de Fase 1)

- **Probado con datos reales (25/8/2026).** Permisos asignados: Admin 10/10,
  Tester 9/10 (sin `comercial_comision`). Cargado a mano: 2 empresas, 2 personas,
  1 obra con las 2 empresas (una con dos roles), 2 personas relacionadas, una de
  ellas referente con 3,5% y 1 prospecto. Verificado en la UI: array de roles,
  `empresa_principal` derivada por prioridad (la obra pasó a mostrar la
  desarrolladora al agregarla), aviso blando de duplicados, unique de CUIT
  (23505 → mensaje mapeado) y referente único (la UI deshabilita la marca y
  explica por qué). Verificado contra la base, simulando cada usuario con
  `set local role authenticated` + `request.jwt.claims`: Tester no ve ninguna
  fila de `comercial_comisiones` (Admin ve 1); Tester editando la relación vía
  `guardar_obra_persona` sin comisión **no borra** la comisión ajena; Tester
  intentando fijar un porcentaje recibe 42501; sin `comercial_gestionar_ajenos`
  ve 0 prospectos ajenos; desactivar la obra cae en cascada sobre prospecto,
  relaciones y comisión; CM002/CM003 bloquean desactivar empresa o persona con
  obras activas. Todo lo destructivo corrió dentro de transacciones con
  `rollback` — la base quedó como estaba.
  **Falta**: mirar la ficha con la sesión de Tester abierta en el browser. Los
  tres lugares donde se dibuja el `%` (`ObraRelaciones`, `ProspectosView`,
  `RelacionPersonaPanel`) están guardados por `verComision && comision`, así que
  no queda ningún `Comisión —` vacío; lo único pendiente es verlo a ojo.
- **`SUPABASE_ACCESS_TOKEN` no está en el entorno.** `npx supabase gen types` falla
  y **escribe su error en el archivo de tipos** si se redirige la salida con `>`.
  Hasta que el token esté, regenerar tipos vía MCP o editar a mano.
- **ABM de `comercial_fuentes`**: la tabla acepta filas nuevas, pero no hay
  pantalla para cargarlas. Se siembran las 9 iniciales. Agregar una hoy es un
  INSERT a mano. Si el usuario lo pide, es una vista más del módulo.
- **Widget de dashboard**: postergado a propósito. Sin datos cargados no dice
  nada. Candidato natural: prospectos por estado, o potencial estimado abierto.
- **Merge de duplicados**: se avisa antes de crear, no se fusionan registros ya
  creados. Si aparecen duplicados reales en producción, se resuelve con una
  función de merge, no a mano.
- **Tests SQL de RLS**: `sql/tests/` tiene los de tareas; comercial no tiene los
  suyos. Lo que más los pide: que un usuario sin `comercial_comision` no pueda
  leer ni borrar una comisión ajena vía `guardar_obra_persona`.

---

## 7. Fase 2 — qué habilita esto

```
PROSPECTO → OPORTUNIDAD → PRESUPUESTO → PEDIDO → INSTALACIÓN → POSTVENTA
```

El presupuestador va a poder recibir como contexto, sin tablas nuevas: obra,
empresas y sus roles, personas y sus roles, referente, fuente, potencial y
estado comercial. Nada de eso hay que rearmarlo.

Lo que Fase 2 sí va a necesitar decidir: si el prospecto ganado se convierte en
otra entidad o cambia de estado, y si la comisión pasa de configurativa a
liquidable (ahí `comercial_comisiones` deja de ser una fila suelta y necesita
historial).
