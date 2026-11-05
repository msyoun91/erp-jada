# Auditoría — Catálogo (2026-11-04)

**Alcance.** Todo lo que existe del módulo en `erp-v2` (`bce183b`):
- el SQL `sql/158`–`165` y `167`–`170` (6.259 líneas), más `sql/166`, que toca la bandeja;
- los 10 tests `sql/tests/catalogo_*.sql` (3.151 casos);
- las decisiones de `decisiones/catalogo/`, `db_schema/catalogo.md` y `database.types.ts`;
- las pantallas: `modules/catalogo/` (7.020 líneas) y `app/(erp-app)/catalogo/`.

**Cómo se verificó.**
- Se leyó entero el SQL, las decisiones, el esquema y el código de las pantallas, y se compararon entre sí.
- Se armó un Postgres 16 local con un stub de Supabase: roles `anon`, `authenticated` y `service_role`, `auth.uid()`,
  `auth.users`, `extensions` y los privilegios por defecto de funciones. Ahí se aplicaron las 170 migraciones en orden, y corren
  limpias. La base usa collation `en-US`, como Supabase.
- Se corrió la suite, `tsc` y `eslint`, y se escribió una prueba propia para cada hallazgo de la base. Lo marcado **reproducido**
  se ejecutó; lo marcado **por lectura** no.
- **No se pudo verificar la deriva contra Supabase.** El MCP de Supabase no conectó en esta sesión, así que no se comparó el
  `md5(prosrc)` de la base real con los archivos. Lo que dice "en Supabase" está por confirmar.
- **Las pantallas no se probaron en el navegador.** Esta sesión tampoco tenía la base real (`BACKLOG.md` dice lo mismo de la que
  las escribió).

## Resumen

La base del módulo es sólida. El modelo de seguridad se cumple en todo lo que se revisó, las reglas viven en Postgres, y la
documentación coincide con el código. La suite pasa entera (**3.151 / 3.151**), `tsc` da 0 errores y `eslint` no marca nada.

El hallazgo con más impacto es de rendimiento. Con la configuración por defecto de Postgres (`jit = on`),
`catalogo_version_revisar` tarda **2,6 s**, y sin JIT 51 ms. Las pantallas la llaman al abrir un borrador o una versión en
revisión, y el editor la vuelve a pedir en cada guardado. Le siguen dos huecos de la base: contenido que entra en piezas ya
sacadas, y un precio 0 cuando no queda ninguna fila. Lo demás son bordes. Ninguno es un problema de permisos.

| # | Severidad | Hallazgo | Dónde |
|---|---|---|---|
| 1 | **Alta** (a confirmar en Supabase) | El JIT hace que revisar, enviar y aprobar tarden ~2,6 s. El editor lo paga en cada guardado | `sql/167` `catalogo_version_frena` y sus pasos |
| 2 | **Media** | Se puede meter contenido en una pieza, un material, una opción o una variable ya sacados. Sobrevive al envío y deja la versión publicada sin poder copiarse | `sql/160` `catalogo_contenido_validar` |
| 3 | **Media** | Si con esas medidas no queda ninguna fila, el precio da **0**, sin mensaje | `sql/163` `catalogo_precio_calcular` |
| 4 | Baja | Hay escrituras de dos pasos en `actions.ts` que no son atómicas: si falla el segundo, el primero ya quedó | `actions.ts` |
| 5 | Baja | Un UPDATE que la RLS no deja pasar se informa como "guardado" | `actions.ts` |
| 6 | Baja (a confirmar) | Las listas se leen enteras, sin paginar. Si pasan el `max-rows` de PostgREST, faltan costos sin aviso | `queries.ts` |
| 7 | Baja | Un servicio fijo frena el peso de su pieza y arma un círculo que el editor no deja resolver | `sql/161` `_sumas`, `sql/167` `_circular` |
| 8 | Baja | Un material múltiple con cantidad 0 igual exige elegir una opción | `sql/167` `catalogo_despiece_entrada` |
| 9 | Baja | Cambiar el tipo de un material o a quién sigue deja opciones huérfanas. Fijan insumos y se copian para siempre | `sql/160`, `sql/167` |
| 10 | Baja | Un INSERT directo crea un paquete con una causa de baja inventada | `sql/160` GRANT INSERT |
| 11 | Baja | Carga de costos: una variante repetida da 23505, y cambiar de moneda sin ningún tipo de cambio da MO001 | `sql/159` |
| 12 | Baja | El parser con muchos paréntesis anidados da 54001 y no CA001 | `sql/158` |
| 13 | Baja | Algunos renombres no pasan por el gerente: un color ofrecido sin variantes, y una categoría vacía que ya está en un % | `sql/159`, `sql/160` |
| 14 | Baja | Sin color, el gerente lee "sin costo a esa fecha", y la causa real es el color | `sql/163` |
| 15 | Baja | En la calculadora, "1.500" se lee 1,5 | `entrada.ts` |
| 16 | Baja (mantenimiento) | Los árboles de las fórmulas son columnas generadas: si cambia el parser, las versiones enviadas no se pueden regenerar | `sql/158`, `sql/160` |
| 17 | Baja | La campanita resuelve todos los avisos activos del catálogo, no solo los 30 que muestra | `sql/165` `catalogo_avisos` |
| 18 | Info | Hay concurrencias sin probar, tests que necesitan datos previos, la carga por script necesita `auth.uid()`, FKs sin índice y otros | varios |

---

## Lo que está bien (verificado)

- **Las funciones DEFINER verifican permisos.** Hay 26 funciones `SECURITY DEFINER`, y las 18 que `authenticated` puede llamar
  chequean el permiso antes de leer: `tiene_permiso`, `_tomar` o `_empezar`. Las 8 restantes son triggers sin EXECUTE.
  Ninguna de las 88 funciones del catálogo tiene EXECUTE para `anon`, y todas tienen `SET search_path`.
- **RLS en las 19 tablas**, también en `catalogo_variables_valores`. `catalogo_bajas` no tiene policy ni GRANT, como corresponde.
  `anon` no tiene ningún privilegio. Los UPDATE son por columna, así que `tipo`, `insumo_id`, `version_id`, `estado` y `numero` no
  se pueden escribir.
- **Las fórmulas no ejecutan SQL dinámico.** El parser no deja pasar `1; drop table`, `(select 1)` ni `pg_sleep`, y evaluar no lee
  tablas. Así se cumple *Las fórmulas se calculan sin SQL dinámico*.
- **Cada cálculo tiene una sola fuente.** El precio parte de `catalogo_despiece`, la baja y el aviso previo usan la misma
  `catalogo_oferta`, y los costos y los % se leen con una sola regla de vigencia. Las pantallas no repiten reglas: el nivel
  15/25/50 % y lo que frena vienen de la base, y la pantalla solo los pinta.
- **La concurrencia está pensada.** Hay `FOR UPDATE` sobre la versión, `FOR SHARE` sobre insumos, variantes, categoría y colores
  antes de `frena`, un advisory lock para los servicios en %, y el lock del material en `sql/169`. Se revisó que los triggers BEFORE
  vean lo confirmado después de esperar el lock.
- **No hay DELETE.** Las bajas son `activo = false`, con índices parciales `WHERE activo`. La excepción de `catalogo_variantes`
  está documentada.
- **Las pantallas cumplen las reglas del repo.**
  - `tsc` y `eslint` limpios, sin `any` ni `dangerouslySetInnerHTML`.
  - Las 38 server actions validan con `safeParse` y revalidan.
  - Cada página verifica su vista en servidor antes de cargar (`notFound`).
  - Los nombres de tabla que llegan del cliente (`sacar`, `ordenar`) están limitados por `z.enum`.
- **Documentación y tipos al día.** `db_schema/catalogo.md` coincide con el SQL en tablas, funciones, errores y forma del JSON,
  incluidos los cambios de `sql/167`–`170`. `database.types.ts` trae todas las tablas y funciones; solo faltan los triggers, como
  siempre con el generador.
- **Sin regresión en notificaciones.** `sql/165` es el `notificaciones_listar` de `sql/156` más la rama del catálogo, y `sql/166`
  solo le suma un `OFFSET 0`. El CHECK de `entidad` conserva las 11 entidades anteriores.
- **Decisiones y código coinciden.** Se revisaron una por una:
  - las reglas de *Qué frena el envío*, con las nuevas de `sql/167` y `170`;
  - los niveles 15/25/50 %, la reversión y las bajas en cascada;
  - el redondeo, la moneda, los mínimos y los avisos;
  - la pareja como sugerencia y la variable según un material.

  Las únicas diferencias son las de los hallazgos 7, 8 y 13.

---

## Hallazgos

### 1. El JIT hace lento todo lo que pasa por `catalogo_version_frena` — Alta, a confirmar en Supabase

**Descartado en Supabase (2026-11-04).** La plataforma trae `jit = off` (`platform-defaults.conf`) y ningún rol lo cambia. `frena` tarda
44–50 ms en un borrador de 2 piezas y 7 materiales (245 ms la primera llamada). No se cambió nada. Lo de abajo vale solo para un Postgres con
`jit = on`, como el local de la auditoría.

**Qué pasa.** Postgres estima 1.000 filas para cada función que devuelve filas. En `catalogo_version_referencias`, esa estimación
se multiplica por subconsultas correlativas: el costo estimado llega a ~640.000, cuando `jit_above_cost` es 100.000 y
`jit_optimize_above_cost` 500.000. Entonces Postgres compila con LLVM en cada llamada. Como las funciones SQL no guardan el plan
entre llamadas, compila de nuevo cada vez. El tiempo es de compilación, no de datos, así que pasa igual con un paquete chico.

**Reproducido** con un paquete de 6 piezas, 36 materiales, 102 fórmulas y 6 casos:

| | `jit = on` (por defecto) | `jit = off` |
|---|---|---|
| `catalogo_version_revisar` (también `enviar` y `aprobar`) | **~2.600 ms** | 51 ms |
| `catalogo_version_referencias` | 820–1.120 ms | 9 ms |
| `catalogo_version_circular` | 1.630–1.680 ms | 33 ms |
| `catalogo_despiece`, `catalogo_precio`, `catalogo_oferta`, `catalogo_baja_aviso` | 10 / 43 / 5 / 14 ms | 9 / 31 / 3 / 13 ms |
| tests `catalogo_ciclo` · `catalogo_precio` · `catalogo_avisos` (con `sql/158`–`165`) | 290 s · 47 s · 46 s | 2,9 s · 2,1 s · 1,3 s |

**Dónde se nota.**
- La ficha de un borrador o de una versión en revisión pide `getFrena` al abrir: `paquetes/versiones/[id]/page.tsx`.
- El editor la pide al abrir, y cada guardado hace `revalidatePath("/catalogo", "layout")`, así que la página se vuelve a armar y
  la pide otra vez.
- La lista de parejas guarda sola medio segundo después de cada cambio (`pantallas.md`).

Con JIT, cada uno de esos pasos espera unos 2,6 s.

**Cómo confirmarlo en Supabase:** correr `SHOW jit;`. Si da `on`, pasa también ahí. También sirve
`EXPLAIN (ANALYZE) SELECT catalogo_version_revisar('<id>')`: si el plan trae la sección `JIT:`, es esto.

**Propuesta, probada en local:** `ALTER FUNCTION public.catalogo_version_frena(uuid) SET jit = off;`. La sesión sigue con
`jit = on` y `revisar` pasa de 2.600 ms a 54 ms. La alternativa es bajar la estimación con `ROWS` en `_formulas`, `_alcance` y
`_referencias`, pero es más frágil.

### 2. Contenido debajo de algo ya sacado del borrador — Media

**Resuelto (2026-11-04, `sql/171`):** CA025. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** `catalogo_contenido_validar` (`sql/160_catalogo_paquetes.sql:306`) impide reactivar lo sacado (CA015), pero no impide
crear o mover algo debajo de un padre sacado. Las FK compuestas no miran `activo`. Se puede:
- insertar un material o una variable en una pieza sacada, o mover uno ahí con `UPDATE pieza_id`;
- insertar una opción en un material sacado, o una condición en una variable sacada;
- insertar un valor de `catalogo_variables_valores` para una opción o una variable sacadas;
- apuntar `requiere_pieza_id`, `sigue_material_id`, `sigue_opcion_id` o `segun_material_id` a algo sacado.

**Reproducido**, también con `sql/167`–`170`. Lucía saca la pieza "Extra" de un borrador y después le inserta un material, con el
mismo permiso `catalogo_armar`. El resultado:
1. `revisar` da `{}`, la versión se envía y Carlos la aprueba. El material no aparece en el despiece, así que el gerente nunca lo
   vio.
2. `catalogo_version_nueva` y `catalogo_paquete_duplicar` desde esa versión publicada fallan con **23502**. La copia no encuentra
   la pieza y deja `pieza_id` en NULL. Técnica tiene que partir de una versión vieja o armar todo de nuevo.
3. Ese material fantasma fija el insumo que usa (CA006), aunque no esté en ninguna pieza activa.
4. `catalogo_version_insumos` y `catalogo_oferta` lo cuentan, porque no filtran `p.activo`, y el despiece no. Si el insumo no tiene
   costo, el envío lo frena por algo que no se ve.

**Cómo se llega sin mala intención.** La decisión acepta que dos personas de Técnica editen el mismo borrador ("Martín puede
cambiar un insumo del borrador de Lucía"). Ahora el editor guarda cada panel por su lado, sin bloquear el borrador. Si Lucía saca
la pieza mientras Martín, con el panel abierto, le suma un material, se llega a este estado.

**Propuesta.** En `catalogo_contenido_validar`, con `NEW.activo`, exigir que cada padre esté activo: pieza, material, opción,
variable, `requiere_pieza_id`, `sigue_material_id`, `sigue_opcion_id` y `segun_material_id`. Es una sola regla y vive en la base,
como pide *Lo que nunca tiene sentido se frena al guardar*.

### 3. Si con esas medidas no queda ninguna fila, el precio da 0 — Media

**Resuelto (2026-11-04, `sql/172`):** sin filas no hay precio, y el mensaje lo dice. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** Si todas las piezas o materiales dan cantidad 0, el despiece sale calculable y sin filas. En
`catalogo_precio_calcular` (`sql/163_catalogo_precio.sql:88`), el costo queda en `coalesce(sum, 0) = 0`, ningún servicio aplica y
el precio da 0.

**Reproducido** con una pieza con cantidad `si ancho > 1000 entonces 1 si no 0`, enviada y aprobada con un caso de ancho 1.500.
Con ancho 500, `catalogo_precio` devuelve `{"precio": 0, "mensaje": null}`.

**Por qué importa.** Una línea en $0 dentro de un presupuesto de 10 ítems baja el total sin que nadie lo note. Es justo lo que las
decisiones evitan en otros lugares: *Sin costo a la fecha pedida, no hay precio*, y nunca toma 0.

**Propuesta.** Sin filas, el precio no da número, con un mensaje propio ("Con estas medidas el paquete no lleva nada").

### 4. Escrituras de dos pasos en `actions.ts` — Baja, por lectura

**Resuelto (2026-11-04, `sql/173`):** las marcas las apaga un trigger, y sumar un color y ordenar son funciones. Lo de abajo describe lo que
pasaba antes.

**Qué pasa.** Cada llamada de supabase-js es su propia transacción. Hay acciones que hacen dos o más:
- **`guardarOpcion`** con `predeterminada`: primero apaga la predeterminada anterior y después guarda la nueva. Si el segundo paso
  falla, el material queda **sin predeterminada**, y nadie lo pidió. Puede fallar por un insumo repetido (23505), otra unidad
  (CA024) o una fórmula que no se entiende (CA001).
- **`marcarColorBase`**: apaga la base y prende otra. Si el segundo falla, la versión queda sin color base.
- **`sumarColorVersion`**: cuenta si hay base y después inserta. Dos altas a la vez pueden marcar dos bases: el índice frena una con
  "Ese color ya está en la versión", que no es lo que pasó.
- **`ordenar`**: un UPDATE por hermano, en paralelo. Si falla uno, queda la mitad renumerada.

**Por qué importa.** *Regla de negocio → Postgres* pide que la orquestación de varios pasos viva en la base. Acá las consecuencias
son chicas, porque el envío frena una base o una predeterminada que falten.

**Propuesta.** Una función `SECURITY INVOKER` por caso, por ejemplo `catalogo_opcion_guardar` o `catalogo_color_base`, que haga los
dos pasos en una transacción.

### 5. Un UPDATE que la RLS no deja pasar se informa como "guardado" — Baja, por lectura

**Resuelto (2026-11-04, `actions.ts`):** 0 filas da "No tenés permiso para hacer esto". También en las que la auditoría no nombraba:
`editarFijo`, `quitarColor`, `activarPaquete`, `guardarVersionDatos`, `guardarValorVariable` y `marcarColorBase`. Lo de abajo describe lo
que pasaba antes.

**Qué pasa.** Con RLS, un UPDATE sin permiso no da error: no encuentra filas y devuelve 0. Pasa lo mismo si el id no existe.
`actions.ts` solo mira `error`, así que esas acciones devuelven `success`: `renombrar*`, `activar*`, `editarInsumo`,
`guardarPieza`, `guardarOpcion`, `guardarCondicion`, `sacar` y `ordenar`. Las que piden `.select("id").single()`
(`guardarVariable`, `guardarMaterial`) sí lo detectan.

**Por qué importa.** La base sigue protegida: es un problema de mensaje, no de seguridad. A quien le sacaron un permiso con la
página abierta, la pantalla le dice "guardado" y no cambió nada.

**Propuesta.** Pedir `.select("id")` en los UPDATE y tratar 0 filas como error ("No se pudo guardar: revisá tus permisos").

### 6. Listas sin paginar contra el `max-rows` de PostgREST — Baja, a confirmar

**Qué pasa.** `getInsumos` lee todos los insumos y todo `catalogo_costos_vigentes()`, una fila por variante con costo.
`getPaquetes` y `getInsumosBasicos` leen todo de una vez. Supabase corta cada respuesta en `max-rows`, que por defecto es 1.000, y
lo hace **sin error**. *El costo del insumo* ya prevé "200 perfiles en 3 colores", que son 600 variantes solo de perfiles.

**Por qué importa.** Pasado ese número, algunas variantes se ven "sin costo" aunque lo tengan. Además, "Cambiar todos (%)" en
`CostosPanel` deja sin tocar las que no trajeron costo.

**Cómo confirmarlo:** ver *Max Rows* en la configuración de la API de Supabase. **Propuesta:** paginar con `.range()` o filtrar
los costos por las variantes que muestra la pantalla.

### 7. El servicio fijo "nunca cuenta para el peso", pero lo frena — Baja

**Resuelto (2026-11-04, `sql/174`):** un material único con un servicio no entra en el peso ni en el espesor, tenga la marca que tenga. Lo de
abajo describe lo que pasaba antes.

**Qué pasa.** *Editor de paquete* dice: "El servicio fijo nunca cuenta para el peso ni para el espesor, y el editor no muestra esa
marca en su fila". Con `cuenta_peso` en true por defecto, el servicio no suma kilos, pero el peso de la pieza igual lo espera:
- `catalogo_despiece_sumas` (`sql/161_catalogo_despiece.sql:366`) espera que todo material con `cuenta_peso` esté calculado;
- `catalogo_version_circular` suma la arista `peso → servicio`.

**Reproducido.** En la pieza Hoja, una Instalación con cantidad `si [peso Hoja] > 40 entonces 2 si no 1` da "Referencia circular
entre P Instalacion, peso Hoja", y la versión no se puede enviar. Con `cuenta_peso = false` en la base calcula bien, pero el
editor no muestra esa marca, así que Técnica no tiene salida. Lo que sí sirve es pasar el servicio a otra pieza (Colocación).

**Propuesta.** En `_sumas` y `_circular`, que un material único cuyo insumo es `servicio` no cuente para el peso ni el espesor.

### 8. Un material múltiple con cantidad 0 igual exige elegir — Baja

**Resuelto (2026-11-04, `sql/175`):** si ninguna opción trae cantidad propia y la del material da 0, no hace falta elegir. Lo de abajo
describe lo que pasaba antes.

**Qué pasa.** `catalogo_despiece_entrada` marca como faltante todo múltiple sin elección ni predeterminado antes de calcular, y
`elegir` se corre antes que la cantidad. Es necesario cuando la opción trae su propia cantidad, pero cuando no la trae, la del
material sola ya sabría que da 0.

**Reproducido.** En una puerta, el material múltiple "Vidrio superior" tiene cantidad `si alto > 2100 entonces 1 si no 0`. Con alto
2.000 y sin elegir, el resultado es "No se puede calcular" (`Vidrio superior: falta elegir una opción`).

**Por qué importa.** Contradice *Primero se calcula la cantidad: si da 0, el material no tiene fila*. Técnica lo puede esquivar con
un predeterminado o con "sin elección".

**Propuesta.** Si ninguna opción trae cantidad propia, calcular la del material antes de exigir la elección. Si no, dejarlo escrito
en *Cómo se calcula*.

### 9. Opciones huérfanas al cambiar el tipo de un material o a quién sigue — Baja, por lectura

**Resuelto (2026-11-04, `sql/176`):** al cambiar, salen las opciones que dejan de aplicar, y el panel lo avisa antes de guardar. Se reprodujo, y
pesaba más de lo que dice abajo: `frena` sí las contaba (`catalogo_version_insumos`), una pareja vieja se podía elegir a mano y fijaba la unidad de
las nuevas (CA024). Los valores de una variable que cambia de material no se tocaron: no se miran ni se copian, como dice *Una variable que no carga
el vendedor*. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** `UPDATE catalogo_materiales SET tipo = …` o `SET sigue_material_id = …` no saca las opciones que ya no corresponden.
Quedan opciones en un material `unico`, o parejas que apuntan a opciones del material que se seguía antes.

El cálculo y `frena` las ignoran. Pero `catalogo_insumos_validar` las cuenta, así que **fijan un insumo que el paquete no usa**, y
`catalogo_version_copiar` las copia a cada versión nueva. Lo mismo pasa con los valores de una variable cuando cambia
`segun_material_id`, como dice `sql/167`, aunque esos al menos no se copian.

**Propuesta.** Sumar a `catalogo_contenido_baja` el caso "cambió `tipo` o `sigue_material_id`", y sacar lo que deja de aplicar,
como ya pasa al sacar.

### 10. Un paquete con una causa de baja inventada — Baja

**Resuelto (2026-11-04, `sql/177`):** el INSERT directo solo alcanza a `activo`. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** `GRANT INSERT ON catalogo_paquetes` es por tabla (`sql/160_catalogo_paquetes.sql:421`), y `sql/162` le sumó
`baja_insumo_id` y `baja_variante_id`.

**Reproducido.** Lucía hace `INSERT … (activo, baja_insumo_id) VALUES (false, <insumo>)` y el paquete queda "De baja por:
<insumo>" sin que esa baja haya existido.

**Propuesta, probada en local:** `REVOKE INSERT ON catalogo_paquetes FROM authenticated; GRANT INSERT (activo) ON catalogo_paquetes
TO authenticated;`. `catalogo_paquete_alta` sigue funcionando, y el INSERT con `baja_insumo_id` da 42501.

### 11. Carga de costos — Baja

**Resuelto (2026-11-04, `sql/178`):** la variante repetida da CA026, y sin tipo de cambio el nivel va en NULL. Lo de abajo describe
lo que pasaba antes.

**Qué pasa.**
- Si la misma variante va dos veces en una carga en bloque, falla con **23505**, sin un mensaje que se entienda. *Reproducido.*
- `catalogo_costos_niveles` pasa el costo anterior a la moneda nueva. Si esa moneda no tiene ningún tipo de cambio cargado hasta
  hoy, la carga entera da **MO001**, y en una carga en bloque una sola fila frena todas. *Reproducido* en una base sin tipos de
  cambio. En producción solo pasa con una moneda que nunca se cargó.

**Propuesta.** Rechazar las variantes repetidas con un código CA y un mensaje claro. Sin tipo de cambio, dejar el nivel en NULL, sin
color, en vez de frenar: el nivel solo avisa.

### 12. El parser con paréntesis muy anidados — Baja

**Resuelto (2026-11-04, `sql/179`):** lo que agota la pila al parsear da CA001, y más de 100 operaciones anidadas no se guardan.
`catalogo_numero_texto` ya no usa máscara. La propuesta de contar paréntesis no alcanzaba: 1.000 signos menos también daban 54001, y
una suma de 999 términos se guardaba y fallaba al calcular. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** Con cientos de paréntesis anidados (600 alcanzan), dentro del tope de 2.000 caracteres, el parser recursivo da
**54001** (`stack depth limit exceeded`) en vez de CA001. *Reproducido.* No hay riesgo de seguridad, porque no se guarda nada, pero
el editor no traduce ese error. En el mismo grupo, `catalogo_numero_texto` muestra `###.###…` desde 10¹⁵.

**Propuesta.** En `catalogo_formula_tokens`, contar la profundidad de los paréntesis y rechazar con CA001 desde 50, por ejemplo.

### 13. Renombres y bajas que no pasan por el gerente — Baja

**Resuelto (2026-11-04, `sql/180`):** el nombre de un color que ofrece una versión enviada queda fijo, y el de una categoría usada en
algún valor de un servicio en %, también. Se miró toda la historia y no solo el valor vigente, como proponía esto, porque revertir devuelve
categorías anteriores. Las bajas no cambian: ya están decididas (`versiones.md`, `insumos.md`). Lo de abajo describe lo que pasaba antes.

Los dos casos se **reprodujeron**:
- **Color.** `catalogo_colores_validar` fija el nombre solo si alguna variante usa el color. Una versión publicada puede ofrecer
  "Negro" sin que ningún insumo tenga variante negra, por ejemplo con todo de color indistinto. Lucía lo renombra a "Rojo fuego" o
  lo da de baja, y el despiece y el precio siguen ofreciéndolo con el nombre nuevo. Choca con el porqué de la decisión: "Renombrar
  'Negro' a 'Negro mate' cambiaba lo que ven vendedor y cliente sin que nadie lo aprobara".
- **Categoría.** Una categoría de insumo vacía, que Ana ya sumó a la Garantía de vidrio, se renombra a "Herrajes especiales". Desde
  ahí, la garantía se cobra sobre lo que Técnica cargue en esa categoría.

**Propuesta.** Que el nombre del color también quede fijo si lo ofrece una versión enviada, y el de la categoría, si un servicio en
% vigente la usa.

### 14. Sin color, el gerente lee "sin costo" — Baja

**Resuelto (2026-11-04, `sql/181`):** una fila de un insumo con colores que no tiene color dice "Falta elegir el color" y no busca costo, así
que tampoco usa el de la variante indistinta apagada. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** Si una fila de un insumo con colores no tiene color, `catalogo_precio_calcular` busca la variante con
`color_id IS NULL`. No la encuentra y dice "Perfil: sin costo a esa fecha", cuando la causa es que no hay color. *Reproducido.*

Además, por lectura: si el insumo fue indistinto antes de pasar a colores, la variante indistinta apagada todavía tiene costo, y el
detalle **da un precio** con ese costo viejo. Solo pasa en borradores, porque `frena` no deja enviar una versión sin colores con
insumos de color.

**Propuesta.** En el cálculo del precio, con un insumo de color y sin color en la fila, decir "Falta elegir el color" y no buscar
costo.

### 15. En la calculadora, "1.500" se lee 1,5 — Baja, por lectura

**Resuelto (2026-11-04, `modules/catalogo/entrada.ts`):** el campo es de texto y no acepta el punto: marca el error ahí mismo y no deja
calcular ni guardar el caso. Lo de abajo describe lo que pasaba antes.

**Qué pasa.** `aEntrada` (`modules/catalogo/entrada.ts`) convierte con `Number(valor.replace(",", "."))`, y el campo es
`type="number"`. Escribir 1.500, como escribe la empresa, da 1,5 mm. El mínimo de la variable lo frena casi siempre, pero el mensaje
de rango no dice que el problema fue el punto. Además, un caso guardado así pasa el envío, porque un valor fuera de rango no frena.
El `BACKLOG.md` ya pide para Presupuestos que el campo de medida rechace `3.00`. Conviene que la calculadora haga lo mismo y use la
misma función.

### 16. Los árboles de las fórmulas no se pueden regenerar — Baja, de mantenimiento

**Resuelto (2026-11-04, `decisiones/catalogo/despiece.md`):** si cambia el parser, la migración reescribe los árboles con `SET EXPRESSION`,
que no pasa por los triggers. No hay migración ahora: la regla se aplica cuando cambie el parser. Lo de abajo describe lo que se encontró, y
la propuesta de desactivar triggers ya no hace falta.

**Qué pasa.** `*_arbol` son columnas `GENERATED … STORED` sobre `catalogo_formula_parsear`, que es IMMUTABLE. Si algún día cambia la
gramática o la forma del árbol, las filas guardadas quedan con el árbol viejo. Para regenerarlas hay que hacer `UPDATE … SET formula =
formula`, y `catalogo_contenido_validar` lo rechaza con CA012 en toda versión que no esté en borrador.

**Propuesta.** Dejarlo escrito en *Las fórmulas se calculan sin SQL dinámico*: un cambio en el parser tiene que ser compatible con
los árboles ya guardados, o traer una migración que los reescriba con los triggers desactivados.

### 17. La campanita crece con el historial del catálogo — Baja

**Resuelto (2026-11-04, `sql/182`):** `catalogo_avisos` recibe los ids de `mias` y resuelve solo esos. Con 1.000 avisos de cambios en %, la
campanita bajó de ~700 ms a ~100 ms, y da las mismas filas. Con 30 no cambia (~80 ms). Lo de abajo describe lo que pasaba antes.

**Qué pasa.** `notificaciones_listar` limita `mias` a 30, pero `JOIN catalogo_avisos()` resuelve **todos** los avisos activos del
catálogo del usuario. Por cada uno, `catalogo_porcentaje_cambio` hace sus propias consultas. Los avisos de cambios en % no
desaparecen solos.

**Medido sin JIT:** 25 ms con 30 avisos activos, 49 ms con 300 y 108 ms con 1.000.

**Propuesta.** Que `catalogo_avisos` reciba los ids de `mias`, o un límite.

### 18. Información (sin acción inmediata)

- **Concurrencia no probada.** Se encontraron tres casos posibles, sin reproducirlos:
  - La baja de un insumo bloquea el insumo y después el paquete, y reactivar bloquea el paquete y después el insumo. Las dos a la
    vez pueden dar un deadlock (40P01). Postgres corta una y la otra pasa.
  - Dos paquetes con el mismo nombre enviados en el mismo instante pasan los dos a revisión. Después, cada uno frena la aprobación
    del otro hasta que se retire uno.
  - Dos `version_nueva` simultáneas del mismo paquete dan 23505 en vez de CA013.
- **Copia entre paquetes.** `catalogo_version_copiar` tiene EXECUTE para `authenticated`. Llamada directo, copia una versión de
  otro paquete como borrador de este y se saltea el CA014 de `version_nueva`. No abre nada que `catalogo_armar` no pueda hacer a mano.
- **Tests que necesitan datos previos. Resuelto (2026-11-04):** los dos crean su categoría y sus insumos, y dan 12 / 12 y 5 / 5 en una
  base vacía. Antes, `catalogo_medidas` y `catalogo_sin_eleccion` tomaban una categoría e insumos que ya existieran y, en una base vacía,
  cortaban con 23502 antes de probar nada.
- **Collation de los tests.** Con collation `C`, `catalogo_ciclo` da 2 fallos por el orden alfabético de "Referencia circular
  entre …". Con `en-US`, como Supabase, pasa entero.
- **Carga inicial por script** (BACKLOG). `catalogo_costos.creado_por`, `catalogo_porcentajes_valores.creado_por` y
  `catalogo_versiones_historia.creado_por` son NOT NULL y salen de `auth.uid()`. Con `service_role` fallan, así que el script tiene
  que fijar `request.jwt.claims` con un usuario real.
- **Precios de referencia.** Calculan 2 precios por caso de cada paquete activo, unos 9 ms cada uno. Con 50 paquetes y 3 casos, son
  unos 3 s por carga de la página.
- **FKs sin índice.** Hay 19 FK sin índice completo: `creado_por`, `revierte_id` y las compuestas `(x_id, version_id)`. El advisor
  de Supabase las va a marcar. Como nunca se borra ni cambia un id, no pesan, y las consultas usan los índices parciales.

---

## Tests

| Test | Casos | Resultado (local, `en-US`, sin JIT) |
|---|---|---|
| `catalogo_formulas` | 87 | 87 / 87 |
| `catalogo_registros` | 235 | 235 / 235 |
| `catalogo_paquetes` | 515 | 515 / 515 |
| `catalogo_despiece` | 659 | 659 / 659 · 4,1 ms por cálculo |
| `catalogo_ciclo` | 714 | 714 / 714 |
| `catalogo_precio` | 328 | 328 / 328 |
| `catalogo_avisos` | 283 | 283 / 283 |
| `catalogo_segun` | 316 | 316 / 316 |
| `catalogo_medidas` | 12 | 12 / 12, con datos previos |
| `catalogo_sin_eleccion` | 5 | 5 / 5, con datos previos |

La suite cubre bien las reglas escritas en las decisiones. Le falta un caso por cada hallazgo 2, 3 y 7 a 10, y una medición de
`catalogo_version_revisar`, que es lo único lento. Las pantallas no tienen tests e2e del catálogo.

## Qué conviene decidir antes de cargar el primer paquete real

**Hallazgo 6**, lo único abierto (2026-11-04): ver *Max Rows* en la configuración de la API de Supabase y decidir cómo leer esas listas.
Lo demás está resuelto o descartado, y lo del 18 no pide acción inmediata.
