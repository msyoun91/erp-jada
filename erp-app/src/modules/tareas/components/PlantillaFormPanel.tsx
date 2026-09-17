"use client";

import { useState } from "react";
import {
  get,
  useFieldArray,
  useForm,
  useFormState,
  useWatch,
  type Control,
  type UseFormRegister,
  type UseFormSetValue,
} from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { ChevronDown, ChevronUp, Plus, X } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { ENTES } from "@/lib/entes";
import { guardarPlantilla } from "../actions";
import {
  EJECUTOR,
  guardarPlantillaSchema,
  type Ente,
  type GuardarPlantillaForm,
  type PasoPlantillaForm,
  type PlantillaCompleta,
  type TareaPlantillaItem,
  type TipoEvento,
  type TipoPlantilla,
} from "../types";
import { AsignadosPicker } from "./AsignadosPicker";
import { Segmentado } from "./Segmentado";
import { SelectorUsuarios } from "./SelectorUsuarios";
import { TEMPERATURA_NIVELES, temperaturaRango } from "./tareaLabels";
import { useTareasContexto } from "./tareasContexto";

type Form = GuardarPlantillaForm;
type Lista = "pasos" | `hilos.${number}.pasos`;
type Paso = `pasos.${number}` | `hilos.${number}.pasos.${number}`;
type CampoConDatos = "titulo_creado" | `hilos.${number}.titulo` | `${Paso}.titulo` | `${Paso}.descripcion`;
type Dato = { codigo: string; label: string; ejemplo: string };
// `valor` es `ente:rol`, como lo guarda la base (sql/060).
type RolOpcion = { valor: string; ente: string; label: string };

const TIPOS = [
  { valor: "tarea", label: "Tarea" },
  { valor: "hilo", label: "Hilo" },
  { valor: "proyecto", label: "Proyecto" },
] as const;

const AYUDA_TIPO: Record<TipoPlantilla, string> = {
  tarea: "Crea una tarea.",
  hilo: "Crea un hilo con sus pasos, encadenados o en paralelo.",
  proyecto: "Crea un proyecto con sus miembros, sus hilos y sus tareas sueltas.",
};

// Atada al enum aunque hoy ningún ente dispare con baja ni reactivación: los
// ofrece `entes.disparos` (sql/068), no esta lista.
const DISPARO: Record<TipoEvento, (un: string) => string> = {
  alta: (un) => `Sola, cuando se crea ${un}`,
  estado: (un) => `Sola, cuando ${un} cambia de estado`,
  relacion_alta: (un) => `Sola, cuando a ${un} se le suma un rol`,
  relacion_baja: (un) => `Sola, cuando a ${un} se le saca un rol`,
  baja: (un) => `Sola, cuando se da de baja ${un}`,
  reactivacion: (un) => `Sola, cuando se reactiva ${un}`,
  compartido: (un) => `Sola, cuando compartís ${un}`,
  revocado: (un) => `Sola, cuando revocás ${un}`,
};

type ModoVence = "sin" | "creacion" | "tras_previo";

// `{si hay ente:rol}…{fin}` y `{si no hay ente:rol}…{fin}`, mismo patrón que
// `rellenar_datos` (sql/065): sin anidar, así que el cuerpo no contiene `{fin}`
// ni otro `{si `.
const BLOQUE = /\{si (no )?hay ([a-z_]+:[a-z_]+)\}((?:[^{]|\{(?!fin\}|si ))*)\{fin\}/g;

function resolverBloques(texto: string, roles: string[]) {
  return texto.replace(BLOQUE, (_, no: string | undefined, rol: string, cuerpo: string) =>
    roles.includes(rol) === !no ? cuerpo : "",
  );
}

// Errores de campos anidados (`hilos.1.pasos.0.titulo`): `get` devuelve lo
// que haya en el camino, sin tipo. El error de una lista entera cae en
// `.root` cuando la lista ya tiene campos montados (así lo anida el resolver).
function mensajeDe(errors: unknown, camino: string): string | null {
  for (const c of [camino, `${camino}.root`]) {
    const e: unknown = get(errors, c);
    if (typeof e === "object" && e !== null && "message" in e && typeof e.message === "string") return e.message;
  }
  return null;
}

function pasoVacio(): PasoPlantillaForm {
  return {
    titulo: "",
    asignados: [EJECUTOR],
    responsable_id: EJECUTOR,
    vence_dias: null,
    vence_tras_previo: false,
    temperatura: 50,
    adjuntos: [],
    condicion: null,
  };
}

function pasoDesdeItem(i: TareaPlantillaItem): PasoPlantillaForm {
  return {
    titulo: i.titulo,
    descripcion: i.descripcion ?? undefined,
    asignados: [...(i.incluir_ejecutor ? [EJECUTOR] : []), ...i.asignados],
    responsable_id: i.responsable_id ?? EJECUTOR,
    vence_dias: i.vence_dias,
    vence_tras_previo: i.vence_tras_previo,
    temperatura: i.temperatura,
    adjuntos: i.adjuntos,
    condicion: i.condicion,
  };
}

function valoresIniciales(p?: PlantillaCompleta): Form {
  if (!p) {
    return {
      nombre: "",
      alcance: "privada",
      tipo: "hilo",
      encadenada: true,
      visibilidad: "privado",
      miembros: [],
      hilos: [],
      pasos: [pasoVacio()],
      disparo_ente: null,
      disparo_evento: null,
      disparo_estado: null,
      disparo_rol: null,
    };
  }
  return {
    id: p.id,
    nombre: p.nombre,
    descripcion: p.descripcion ?? undefined,
    alcance: p.alcance,
    tipo: p.tipo,
    titulo_creado: p.titulo_creado ?? undefined,
    encadenada: p.encadenada,
    visibilidad: p.visibilidad,
    miembros: p.miembros,
    hilos: p.hilos.map((h) => ({
      titulo: h.titulo,
      encadenada: h.encadenada,
      pasos: p.items.filter((i) => i.hilo_id === h.id).map(pasoDesdeItem),
    })),
    pasos: p.items.filter((i) => !i.hilo_id).map(pasoDesdeItem),
    disparo_ente: p.disparo_ente,
    disparo_evento: p.disparo_evento,
    disparo_estado: p.disparo_estado,
    disparo_rol: p.disparo_rol,
  };
}

// Crear y editar en el mismo panel (prop `plantilla`). Guardar reemplaza los
// pasos enteros (sql/053), así que el form no lleva ids de paso.
export function PlantillaFormPanel({
  plantilla,
  entes,
  puedeSistema,
  onClose,
}: {
  plantilla?: PlantillaCompleta;
  entes: Ente[];
  puedeSistema: boolean;
  onClose: () => void;
}) {
  const { usuarios } = useTareasContexto();
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    setValue,
    getValues,
    formState: { errors, isDirty },
  } = useForm<Form>({
    resolver: zodResolver(guardarPlantillaSchema),
    defaultValues: valoresIniciales(plantilla),
  });

  const tipo = useWatch({ control, name: "tipo" });
  const nombre = useWatch({ control, name: "nombre" });
  const encadenada = useWatch({ control, name: "encadenada" }) ?? true;
  const alcance = useWatch({ control, name: "alcance" }) ?? "privada";
  const miembros = useWatch({ control, name: "miembros" }) ?? [];
  const disparoEnte = useWatch({ control, name: "disparo_ente" }) ?? null;
  const disparoEvento = useWatch({ control, name: "disparo_evento" }) ?? null;
  // Los que la RLS dejó ver (`getEntes`), un renglón por evento que dispara.
  const disparos = entes.flatMap((e) =>
    ENTES[e.codigo]
      ? e.disparos.map((evento) => ({
          valor: `${e.codigo}:${evento}`,
          ente: e.codigo,
          evento,
          label: DISPARO[evento](ENTES[e.codigo].un),
        }))
      : [],
  );
  const enteElegido = disparoEnte ? ENTES[disparoEnte] : undefined;
  const datosDelEnte = entes.find((e) => e.codigo === disparoEnte)?.datos ?? [];
  // Los que la base ofrece (`entes.datos`) y la UI sabe nombrar.
  const datos: Dato[] = datosDelEnte.flatMap((codigo) => {
    const d = enteElegido?.datos[codigo];
    return d ? [{ codigo, ...d }] : [];
  });
  // Los roles del ente que dispara: se adjuntan a la tarea o la condicionan.
  const roles: RolOpcion[] = Object.entries(enteElegido?.roles ?? {}).flatMap(([ente, porRol]) =>
    Object.entries(porRol).map(([rol, label]) => ({ valor: `${ente}:${rol}`, ente, label })),
  );

  // Cambiar de tipo reacomoda lo cargado en vez de tirarlo: los pasos de un
  // hilo pasan a ser un hilo del proyecto, y al revés se aplanan en orden.
  function cambiarTipo(nuevo: TipoPlantilla) {
    const hilos = getValues("hilos") ?? [];
    const pasos = getValues("pasos") ?? [];
    const todos = [...hilos.flatMap((h) => h.pasos), ...pasos];
    const opciones = { shouldDirty: true };

    if (nuevo === "proyecto") {
      if (tipo === "hilo" && pasos.length > 0) {
        setValue(
          "hilos",
          [{ titulo: getValues("titulo_creado") || getValues("nombre") || "Hilo", encadenada: getValues("encadenada") ?? true, pasos }],
          opciones,
        );
        setValue("pasos", [], opciones);
      }
    } else {
      if (nuevo === "tarea" && todos.length > 1) {
        toast.info("Una plantilla de tarea tiene un solo paso: quedó el primero");
      }
      setValue("pasos", nuevo === "tarea" ? [todos[0] ?? pasoVacio()] : todos.length > 0 ? todos : [pasoVacio()], opciones);
      setValue("hilos", [], opciones);
      setValue("miembros", [], opciones);
    }
    setValue("tipo", nuevo, opciones);
  }

  async function onSubmit(data: Form) {
    setEnviando(true);
    const result = await guardarPlantilla({ ...data, id: plantilla?.id });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(plantilla ? "Plantilla actualizada" : "Plantilla creada");
    onClose();
  }

  return (
    <RightPanel
      title={plantilla ? "Editar plantilla" : "Nueva plantilla"}
      subtitle={plantilla?.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-plantilla" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : plantilla ? "Guardar" : "Crear plantilla"}
          </button>
        </>
      }
    >
      <form
        id="form-plantilla"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Nombre</label>
          <input aria-required className={`input ${errors.nombre ? "input-error" : ""}`} {...register("nombre")} />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea rows={2} className="input" {...register("descripcion")} />
        </div>

        {/* El alcance no cambia después de crear: una privada no se vuelve de
            sistema ni cambia de dueño (sql/053, fuera del GRANT UPDATE). */}
        <div>
          <label className="t-label mb-1 block">Alcance</label>
          {!plantilla && puedeSistema && (
            <div className="mb-1">
              <Segmentado
                etiqueta="Alcance"
                opciones={[
                  { valor: "privada", label: "Privada" },
                  { valor: "sistema", label: "De sistema" },
                ]}
                valor={alcance}
                onChange={(v) => setValue("alcance", v, { shouldDirty: true })}
              />
            </div>
          )}
          <p className="t-caption">
            {alcance === "sistema"
              ? "De sistema: la usa todo el que tiene Plantillas. La modifican quienes tienen «Plantillas de sistema»."
              : "Privada: solo vos la ves, la modificás y la usás."}
          </p>
        </div>

        <div>
          <label className="t-label mb-1 block">Crea</label>
          <div className="mb-1">
            <Segmentado etiqueta="Tipo de plantilla" opciones={TIPOS} valor={tipo} onChange={cambiarTipo} />
          </div>
          <p className="t-caption">{AYUDA_TIPO[tipo]}</p>
        </div>

        {(disparos.length > 0 || enteElegido) && (
          <div>
            <label className="t-label mb-1 block">Cuándo se usa</label>
            <select
              aria-label="Cuándo se usa"
              className="input"
              value={disparoEnte && disparoEvento ? `${disparoEnte}:${disparoEvento}` : ""}
              onChange={(e) => {
                const elegido = disparos.find((d) => d.valor === e.target.value);
                const opciones = { shouldDirty: true };
                setValue("disparo_ente", elegido?.ente ?? null, opciones);
                setValue("disparo_evento", elegido?.evento ?? null, opciones);
                setValue("disparo_estado", null, opciones);
                setValue("disparo_rol", null, opciones);
              }}
            >
              <option value="">A mano, desde esta vista</option>
              {disparos.map((d) => (
                <option key={d.valor} value={d.valor}>
                  {d.label}
                </option>
              ))}
            </select>
            {enteElegido && (
              <>
                {disparoEvento === "estado" && (
                  <select
                    aria-label="Estado que la dispara"
                    className={`input mt-2 ${errors.disparo_estado ? "input-error" : ""}`}
                    {...register("disparo_estado", { setValueAs: (v) => v || null })}
                  >
                    <option value="">Elegí el estado…</option>
                    {Object.entries(enteElegido.estados ?? {}).map(([valor, label]) => (
                      <option key={valor} value={valor}>
                        Cuando pasa a «{label}»
                      </option>
                    ))}
                  </select>
                )}
                {errors.disparo_estado && <p className="input-error-text">{errors.disparo_estado.message}</p>}
                {(disparoEvento === "relacion_alta" || disparoEvento === "relacion_baja") && (
                  <select
                    aria-label="Rol que la dispara"
                    className={`input mt-2 ${errors.disparo_rol ? "input-error" : ""}`}
                    {...register("disparo_rol", { setValueAs: (v) => v || null })}
                  >
                    <option value="">Elegí el rol…</option>
                    {[...new Set(roles.map((r) => r.ente))].map((ente) => (
                      <optgroup key={ente} label={`${ENTES[ente]?.nombre ?? ente} con rol…`}>
                        {roles
                          .filter((r) => r.ente === ente)
                          .map((r) => (
                            <option key={r.valor} value={r.valor}>
                              {r.label}
                            </option>
                          ))}
                      </optgroup>
                    ))}
                  </select>
                )}
                {errors.disparo_rol && <p className="input-error-text">{errors.disparo_rol.message}</p>}
                <p className="t-caption mt-1">
                  Corre para quien hace el cambio, con sus permisos, y solo si la tiene activada:{" "}
                  {alcance === "sistema"
                    ? "cada uno la activa para sí desde Plantillas."
                    : "vos la tenés activada desde que la guardás."}
                </p>
                {datos.length > 0 && (
                  <p className="t-caption mt-1">
                    Debajo de cada texto, tocá un dato para sumarlo: al crearse se completa con el de {enteElegido.el}.
                    Quien recibe la tarea lo lee aunque no pueda abrir {enteElegido.el}.
                  </p>
                )}
              </>
            )}
          </div>
        )}

        {tipo !== "tarea" && (
          <div>
            <label className="t-label mb-1 block">
              {tipo === "proyecto" ? "Nombre del proyecto que crea" : "Título del hilo que crea"}
            </label>
            <input
              className={`input ${errors.titulo_creado ? "input-error" : ""}`}
              placeholder={nombre}
              {...register("titulo_creado")}
            />
            {errors.titulo_creado && <p className="input-error-text">{errors.titulo_creado.message}</p>}
            <DatosChips control={control} setValue={setValue} nombre="titulo_creado" datos={datos} roles={roles} />
            <p className="t-caption mt-1">Vacío = el nombre de la plantilla.</p>
          </div>
        )}

        {tipo === "proyecto" && (
          <>
            <div>
              <label className="t-label mb-1 block">Visibilidad del proyecto</label>
              <select className="input" {...register("visibilidad")}>
                <option value="privado">Privado</option>
                <option value="publico">Público</option>
              </select>
            </div>
            <div>
              <label className="t-label mb-1 block">Miembros del proyecto</label>
              <p className="t-caption mb-1">
                Quien use la plantilla se suma solo. Solo los miembros pueden recibir tareas del proyecto.
              </p>
              <SelectorUsuarios
                opciones={usuarios}
                seleccionados={miembros}
                onChange={(ids) => setValue("miembros", ids, { shouldDirty: true, shouldValidate: true })}
                nombreDe={(id) => usuarios.find((u) => u.id === id)?.nombre ?? "Usuario inactivo"}
                sinOpciones="No hay usuarios activos."
              />
            </div>
          </>
        )}

        {plantilla && (
          <p className="t-caption">
            Los cambios aplican a los próximos usos — lo que ya se creó desde esta plantilla no se toca.
          </p>
        )}

        {tipo === "tarea" && (
          <div>
            <label className="t-label t-label-req mb-2 block">Tarea</label>
            <PasoEditor
              control={control}
              register={register}
              setValue={setValue}
              datos={datos}
              roles={roles}
              nombre="pasos.0"
              etiqueta="Tarea"
              miembros={null}
              puedeTrasPrevio={false}
            />
          </div>
        )}

        {tipo === "hilo" && (
          <div>
            <label className="t-label mb-1 block">Pasos</label>
            <ModoCadena valor={encadenada} onChange={(v) => setValue("encadenada", v, { shouldDirty: true })} />
            <ListaPasos
              control={control}
              register={register}
              setValue={setValue}
              datos={datos}
              roles={roles}
              nombre="pasos"
              modo={encadenada ? "cadena" : "paralelo"}
              miembros={null}
              agregar="Agregar paso"
            />
          </div>
        )}

        {tipo === "proyecto" && (
          <>
            <HilosEditor
              control={control}
              register={register}
              setValue={setValue}
              datos={datos}
              roles={roles}
              miembros={miembros}
            />
            <ListaPasos
              control={control}
              register={register}
              setValue={setValue}
              datos={datos}
              roles={roles}
              nombre="pasos"
              titulo="Tareas sueltas"
              ayuda="Tareas del proyecto que no esperan a nada."
              modo="sueltas"
              miembros={miembros}
              agregar="Agregar tarea suelta"
            />
          </>
        )}

        {/* Las listas muestran su propio error; la de tarea no tiene lista. */}
        {tipo === "tarea" && mensajeDe(errors, "pasos") && (
          <p className="input-error-text">{mensajeDe(errors, "pasos")}</p>
        )}
        {errors.tipo && <p className="input-error-text">{errors.tipo.message}</p>}
      </form>
    </RightPanel>
  );
}

type Comunes = {
  control: Control<Form>;
  register: UseFormRegister<Form>;
  setValue: UseFormSetValue<Form>;
  datos: Dato[];
  roles: RolOpcion[];
};

// Un chip por dato: tocarlo inserta `{dato}` donde quedó el cursor del campo.
// Clic y no arrastre: no hay librería de dnd y el arrastre nativo no anda en
// touch. El chip va afuera del campo porque adentro pediría un editor
// enriquecido; en la base el texto sigue siendo `{dato}`. Con roles, "Texto
// solo si…" envuelve lo seleccionado en un bloque (sql/065).
function DatosChips({
  control,
  setValue,
  nombre,
  datos,
  roles,
}: Pick<Comunes, "control" | "setValue" | "datos" | "roles"> & { nombre: CampoConDatos }) {
  const texto = (useWatch({ control, name: nombre }) as string | undefined) ?? "";
  if (datos.length === 0 && roles.length === 0) return null;

  // El campo es de RHF (sin ref propia): se lo busca en el form del control
  // que se tocó. `cambio` recibe el valor y la selección, y devuelve el valor
  // nuevo y dónde queda el cursor.
  function editar(
    elemento: HTMLButtonElement | HTMLSelectElement,
    cambio: (valor: string, inicio: number, fin: number) => [string, number],
  ) {
    const campo = elemento.form?.elements.namedItem(nombre);
    if (!(campo instanceof HTMLInputElement || campo instanceof HTMLTextAreaElement)) return;
    const inicio = campo.selectionStart ?? campo.value.length;
    const [valor, cursor] = cambio(campo.value, inicio, campo.selectionEnd ?? inicio);
    setValue(nombre, valor, { shouldDirty: true, shouldValidate: true });
    campo.focus();
    campo.setSelectionRange(cursor, cursor);
  }

  function insertar(boton: HTMLButtonElement, codigo: string) {
    const dato = `{${codigo}}`;
    editar(boton, (v, i, f) => [v.slice(0, i) + dato + v.slice(f), i + dato.length]);
  }

  // `!ente:rol` es "si no hay". Sin selección, el cursor queda adentro del bloque.
  function envolver(select: HTMLSelectElement, rol: string) {
    const abre = `{si ${rol.startsWith("!") ? "no " : ""}hay ${rol.replace(/^!/, "")}}`;
    const cierra = "{fin}";
    editar(select, (v, i, f) => [
      v.slice(0, i) + abre + v.slice(i, f) + cierra + v.slice(f),
      i === f ? i + abre.length : f + abre.length + cierra.length,
    ]);
  }

  // Mismo reemplazo que `rellenar_datos`, con el ejemplo de cada dato. Con
  // bloques, los dos extremos: con todos los roles que nombra y sin ninguno.
  const conDatos = (t: string) => datos.reduce((acc, d) => acc.replaceAll(`{${d.codigo}}`, d.ejemplo), t);
  const nombrados = [...new Set(Array.from(texto.matchAll(BLOQUE), (m) => m[2]))];
  const nombres = nombrados.map((rol) => (roles.find((r) => r.valor === rol)?.label ?? rol).toLowerCase());
  const ejemplos =
    nombrados.length === 0
      ? [{ caso: "", texto: conDatos(texto) }]
      : [
          { caso: `Con ${new Intl.ListFormat("es").format(nombres)}: `, texto: conDatos(resolverBloques(texto, nombrados)) },
          { caso: `Sin ${nombres.length === 1 ? nombres[0] : "ninguno"}: `, texto: conDatos(resolverBloques(texto, [])) },
        ];

  return (
    <div className="mt-1">
      <div className="flex flex-wrap items-center gap-x-1.5">
        {datos.map((d) => (
          <button
            key={d.codigo}
            type="button"
            aria-label={`Sumar «${d.label}» al texto`}
            className="tap-target group inline-flex items-center"
            onClick={(e) => insertar(e.currentTarget, d.codigo)}
          >
            <span className="t-caption inline-flex items-center gap-1 rounded-full bg-brand-50 px-2.5 py-0.5 font-medium text-brand-700 ring-brand-500 group-hover:ring-1">
              <Plus size={12} />
              {d.label}
            </span>
          </button>
        ))}
        {roles.length > 0 && (
          <select
            aria-label="Texto solo si…"
            className="input my-1 w-auto"
            value=""
            onChange={(e) => e.target.value && envolver(e.currentTarget, e.target.value)}
          >
            <option value="">Texto solo si…</option>
            <OpcionesRol roles={roles} />
          </select>
        )}
      </div>
      {(nombrados.length > 0 || ejemplos[0].texto !== texto) && (
        <div className="t-caption">
          Así se va a ver:{" "}
          {ejemplos.map((e) => (
            <p key={e.caso} className={nombrados.length > 0 ? "ml-3" : "inline"}>
              {e.caso}
              <span className="text-text-primary">{e.texto}</span>
            </p>
          ))}
        </div>
      )}
    </div>
  );
}

// Los roles del ente que dispara, en dos grupos: "hay" (`ente:rol`) y "no hay"
// (`!ente:rol`). Lo usan la condición del paso y los bloques de texto.
function OpcionesRol({ roles }: { roles: RolOpcion[] }) {
  const entes = [...new Set(roles.map((r) => r.ente))];
  return (
    <>
      {[false, true].flatMap((no) =>
        entes.map((ente) => (
          <optgroup key={`${no}${ente}`} label={`Si la obra ${no ? "no tiene" : "tiene"} ${ENTES[ente]?.un ?? ente} con rol…`}>
            {roles
              .filter((r) => r.ente === ente)
              .map((r) => (
                <option key={r.valor} value={no ? `!${r.valor}` : r.valor}>
                  {r.label}
                </option>
              ))}
          </optgroup>
        )),
      )}
    </>
  );
}

function HilosEditor({ control, register, setValue, datos, roles, miembros }: Comunes & { miembros: string[] }) {
  const { fields, append, remove, move } = useFieldArray({ control, name: "hilos" });
  const { errors } = useFormState({ control, name: "hilos" });
  const hilos = useWatch({ control, name: "hilos" });

  return (
    <div>
      <label className="t-label mb-1 block">Hilos</label>
      <p className="t-caption mb-2">Cada hilo elige si sus pasos van encadenados o en paralelo.</p>
      <div className="flex flex-col gap-3">
        {fields.map((field, h) => (
          <div key={field.id} className="rounded-lg border border-border p-3">
            <div className="mb-3">
              <div className="flex items-center gap-2">
                <input
                  aria-label={`Título del hilo ${h + 1}`}
                  placeholder="Título del hilo"
                  className={`input ${mensajeDe(errors, `hilos.${h}.titulo`) ? "input-error" : ""}`}
                  {...register(`hilos.${h}.titulo`)}
                />
                <BotonesOrden
                  indice={h}
                  total={fields.length}
                  onMover={move}
                  onQuitar={remove}
                  minimo={0}
                  que="hilo"
                />
              </div>
              {mensajeDe(errors, `hilos.${h}.titulo`) && (
                <p className="input-error-text">{mensajeDe(errors, `hilos.${h}.titulo`)}</p>
              )}
              <DatosChips control={control} setValue={setValue} nombre={`hilos.${h}.titulo`} datos={datos} roles={roles} />
            </div>
            <ModoCadena
              valor={hilos?.[h]?.encadenada ?? true}
              onChange={(v) => setValue(`hilos.${h}.encadenada`, v, { shouldDirty: true })}
            />
            <ListaPasos
              control={control}
              register={register}
              setValue={setValue}
              datos={datos}
              roles={roles}
              nombre={`hilos.${h}.pasos`}
              modo={(hilos?.[h]?.encadenada ?? true) ? "cadena" : "paralelo"}
              miembros={miembros}
              agregar="Agregar paso"
            />
          </div>
        ))}
      </div>
      <button
        type="button"
        className="btn btn-ghost btn-sm mt-2"
        onClick={() => append({ titulo: "", encadenada: true, pasos: [pasoVacio()] })}
      >
        <Plus size={14} />
        Agregar hilo
      </button>
    </div>
  );
}

function ListaPasos({
  control,
  register,
  setValue,
  datos,
  roles,
  nombre,
  titulo,
  ayuda,
  modo,
  miembros,
  agregar,
}: Comunes & {
  nombre: Lista;
  titulo?: string;
  ayuda?: string;
  modo: "cadena" | "paralelo" | "sueltas";
  miembros: string[] | null;
  agregar: string;
}) {
  // Las dos listas (`pasos` y la de cada hilo) tienen el mismo elemento.
  const { fields, append, remove, move } = useFieldArray({ control, name: nombre as "pasos" });
  const { errors } = useFormState({ control, name: nombre });
  const errorDeLista = mensajeDe(errors, nombre);

  return (
    <div>
      {titulo && <label className="t-label mb-1 block">{titulo}</label>}
      {ayuda && <p className="t-caption mb-2">{ayuda}</p>}
      <div className="flex flex-col gap-2">
        {fields.map((field, i) => (
          <PasoEditor
            key={field.id}
            control={control}
            register={register}
            setValue={setValue}
            datos={datos}
            roles={roles}
            nombre={`${nombre}.${i}`}
            etiqueta={modo === "sueltas" ? `Tarea ${i + 1}` : `Paso ${i + 1}`}
            miembros={miembros}
            puedeTrasPrevio={modo === "cadena" && i > 0}
            orden={
              <BotonesOrden
                indice={i}
                total={fields.length}
                onMover={move}
                onQuitar={remove}
                minimo={modo === "sueltas" ? 0 : 1}
                que={modo === "sueltas" ? "tarea" : "paso"}
              />
            }
          />
        ))}
      </div>
      {errorDeLista && <p className="input-error-text">{errorDeLista}</p>}
      <button type="button" className="btn btn-ghost btn-sm mt-2" onClick={() => append(pasoVacio())}>
        <Plus size={14} />
        {agregar}
      </button>
    </div>
  );
}

// Encadenados: cada paso espera al anterior. En paralelo: ninguno espera (sql/057).
function ModoCadena({ valor, onChange }: { valor: boolean; onChange: (encadenada: boolean) => void }) {
  return (
    <div className="mb-2">
      <Segmentado
        etiqueta="Cómo se habilitan los pasos"
        opciones={[
          { valor: "cadena", label: "Encadenados" },
          { valor: "paralelo", label: "En paralelo" },
        ]}
        valor={valor ? "cadena" : "paralelo"}
        onChange={(v) => onChange(v === "cadena")}
      />
      <p className="t-caption mt-1">
        {valor
          ? "Cada paso se habilita al completar el anterior: el orden manda."
          : "Todos se habilitan juntos; el orden es solo cómo se listan."}
      </p>
    </div>
  );
}

// Los roles del registro en un paso (sql/060). Adjuntar suma a la tarea un chip
// que abre la ficha de quien tenga ese rol; la condición saltea el paso si,
// cuando la plantilla corre, nadie lo tiene (o, negada, si alguien lo tiene).
function RolesPaso({
  control,
  setValue,
  nombre,
  roles,
}: Pick<Comunes, "control" | "setValue" | "roles"> & { nombre: Paso }) {
  const adjuntos = (useWatch({ control, name: `${nombre}.adjuntos` }) as string[] | undefined) ?? [];
  const condicion = (useWatch({ control, name: `${nombre}.condicion` }) as string | null | undefined) ?? null;
  const entes = [...new Set(roles.map((r) => r.ente))];

  function alternar(valor: string) {
    setValue(
      `${nombre}.adjuntos`,
      adjuntos.includes(valor) ? adjuntos.filter((a) => a !== valor) : [...adjuntos, valor],
      { shouldDirty: true },
    );
  }

  return (
    <>
      <div>
        <label className="t-label mb-1 block">Adjuntar a la tarea</label>
        <p className="t-caption mb-2">Quien la recibe ve un chip que abre la ficha de quien tenga ese rol en la obra.</p>
        {entes.map((ente) => (
          <div key={ente} className="mb-2">
            <p className="t-caption mb-1">{ENTES[ente]?.nombre ?? ente}</p>
            <div className="flex flex-wrap gap-1.5" role="group" aria-label={`Adjuntar — ${ENTES[ente]?.nombre ?? ente}`}>
              {roles
                .filter((r) => r.ente === ente)
                .map((r) => {
                  const activo = adjuntos.includes(r.valor);
                  return (
                    <button
                      key={r.valor}
                      type="button"
                      aria-pressed={activo}
                      className={`tap-target t-caption rounded-full border px-2.5 py-0.5 ${
                        activo ? "border-brand-500 bg-brand-50 font-semibold text-brand-700" : "border-border text-text-tertiary"
                      }`}
                      onClick={() => alternar(r.valor)}
                    >
                      {r.label}
                    </button>
                  );
                })}
            </div>
          </div>
        ))}
      </div>

      <div>
        <label className="t-label mb-1 block">Se crea</label>
        <select
          aria-label="Cuándo se crea este paso"
          className="input"
          value={condicion ?? ""}
          onChange={(e) => setValue(`${nombre}.condicion`, e.target.value || null, { shouldDirty: true })}
        >
          <option value="">Siempre</option>
          <OpcionesRol roles={roles} />
        </select>
        {condicion && (
          <p className="t-caption mt-1">Si se saltea, el paso siguiente espera al anterior que sí se creó.</p>
        )}
      </div>
    </>
  );
}

// ↑↓ y no drag & drop: no hay librería de dnd en el proyecto y en una cadena
// el orden es la regla.
function BotonesOrden({
  indice,
  total,
  onMover,
  onQuitar,
  minimo,
  que,
}: {
  indice: number;
  total: number;
  onMover: (desde: number, hasta: number) => void;
  onQuitar: (indice: number) => void;
  minimo: number;
  que: string;
}) {
  return (
    <div className="flex shrink-0 items-center">
      <button
        type="button"
        className="btn btn-ghost btn-sm"
        onClick={() => onMover(indice, indice - 1)}
        disabled={indice === 0}
        aria-label={`Subir ${que}`}
      >
        <ChevronUp size={14} />
      </button>
      <button
        type="button"
        className="btn btn-ghost btn-sm"
        onClick={() => onMover(indice, indice + 1)}
        disabled={indice === total - 1}
        aria-label={`Bajar ${que}`}
      >
        <ChevronDown size={14} />
      </button>
      <button
        type="button"
        className="btn btn-ghost btn-sm"
        onClick={() => onQuitar(indice)}
        disabled={total <= minimo}
        aria-label={`Quitar ${que}`}
      >
        <X size={14} />
      </button>
    </div>
  );
}

function PasoEditor({
  control,
  register,
  setValue,
  datos,
  roles,
  nombre,
  etiqueta,
  miembros,
  puedeTrasPrevio,
  orden,
}: Comunes & {
  nombre: Paso;
  etiqueta: string;
  miembros: string[] | null;
  puedeTrasPrevio: boolean;
  orden?: React.ReactNode;
}) {
  const { usuarios } = useTareasContexto();
  const { errors } = useFormState({ control, name: nombre });
  const paso = useWatch({ control, name: nombre }) as PasoPlantillaForm | undefined;
  const [abierto, setAbierto] = useState(!paso?.titulo);
  const [modoVence, setModoVence] = useState<ModoVence>(
    paso?.vence_dias == null ? "sin" : paso.vence_tras_previo && puedeTrasPrevio ? "tras_previo" : "creacion",
  );

  const conError = get(errors, nombre) != null;
  const errorTitulo = mensajeDe(errors, `${nombre}.titulo`);
  const errorDias = mensajeDe(errors, `${nombre}.vence_dias`);
  const visible = abierto || conError;
  const temperatura = Number(paso?.temperatura) || 50;
  const modo: ModoVence = modoVence === "tras_previo" && !puedeTrasPrevio ? "creacion" : modoVence;

  // Se lee así cuando el paso está plegado: sin abrirlo, qué hace.
  const nombreDe = (id: string) =>
    id === EJECUTOR ? "Quien la use" : (usuarios.find((u) => u.id === id)?.nombre ?? "Usuario inactivo");
  const resumen = [
    (paso?.asignados ?? []).map(nombreDe).join(", "),
    paso?.vence_dias == null
      ? "Sin vencimiento"
      : `Vence a ${paso.vence_dias} d ${modo === "tras_previo" ? "del paso anterior" : "de creada"}`,
    temperaturaRango(temperatura).label,
    paso?.condicion &&
      `Solo si ${paso.condicion.startsWith("!") ? "no " : ""}hay ${(
        roles.find((r) => r.valor === paso.condicion?.replace(/^!/, ""))?.label ?? paso.condicion
      ).toLowerCase()}`,
  ]
    .filter(Boolean)
    .join(" · ");

  function cambiarModo(v: ModoVence) {
    setModoVence(v);
    const opciones = { shouldDirty: true };
    setValue(`${nombre}.vence_tras_previo`, v === "tras_previo", opciones);
    if (v === "sin") setValue(`${nombre}.vence_dias`, null, opciones);
    else if (paso?.vence_dias == null) setValue(`${nombre}.vence_dias`, 3, opciones);
  }

  return (
    <div className={`rounded-lg border p-3 ${conError ? "border-error" : "border-border"}`}>
      <div className="flex items-center gap-2">
        <span className="t-caption w-14 shrink-0">{etiqueta}</span>
        <input
          aria-required
          aria-label={`Título — ${etiqueta}`}
          placeholder="Título"
          className={`input ${errorTitulo ? "input-error" : ""}`}
          {...register(`${nombre}.titulo`)}
        />
        {orden}
      </div>
      {errorTitulo && <p className="input-error-text">{errorTitulo}</p>}
      <DatosChips control={control} setValue={setValue} nombre={`${nombre}.titulo`} datos={datos} roles={roles} />

      <button
        type="button"
        className="tap-target t-caption mt-2 flex w-full items-center gap-1 text-left"
        aria-expanded={visible}
        onClick={() => setAbierto(!visible)}
      >
        {visible ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
        {visible ? "Ocultar detalles" : <span className="truncate">{resumen}</span>}
      </button>

      {visible && (
        <div className="mt-3 flex flex-col gap-4">
          <div>
            <label className="t-label mb-1 block">Descripción</label>
            <textarea rows={2} className="input" {...register(`${nombre}.descripcion`)} />
            <DatosChips control={control} setValue={setValue} nombre={`${nombre}.descripcion`} datos={datos} roles={roles} />
          </div>

          <AsignadosPicker
            control={control}
            miembros={miembros}
            campoAsignados={`${nombre}.asignados`}
            campoResponsable={`${nombre}.responsable_id`}
            conEjecutor
          />

          <div>
            <label className="t-label mb-1 block">Vencimiento</label>
            <Segmentado
              etiqueta="Vencimiento"
              opciones={[
                { valor: "sin", label: "Sin vencimiento" },
                { valor: "creacion", label: "Desde que se crea" },
                ...(puedeTrasPrevio ? [{ valor: "tras_previo" as const, label: "Tras el paso anterior" }] : []),
              ]}
              valor={modo}
              onChange={cambiarModo}
            />
            {modo !== "sin" && (
              <div className="mt-2 flex items-center gap-2">
                <input
                  type="number"
                  min={1}
                  aria-label="Días"
                  className={`input w-20 ${errorDias ? "input-error" : ""}`}
                  {...register(`${nombre}.vence_dias`, {
                    setValueAs: (v) => (v === "" || v == null ? null : Number(v)),
                  })}
                />
                <span className="t-caption">
                  {modo === "tras_previo" ? "días después de completar el anterior" : "días después de crearse"}
                </span>
              </div>
            )}
            {errorDias && <p className="input-error-text">{errorDias}</p>}
          </div>

          <div>
            <label className="t-label mb-1 block">Temperatura</label>
            <div className="flex flex-wrap gap-1" role="group" aria-label="Temperatura">
              {TEMPERATURA_NIVELES.map((nivel) => {
                const activo = temperaturaRango(temperatura).label === nivel.label;
                return (
                  <button
                    key={nivel.label}
                    type="button"
                    aria-pressed={activo}
                    className={`btn btn-sm ${activo ? temperaturaRango(nivel.valor).selector : "btn-secondary"}`}
                    onClick={() => setValue(`${nombre}.temperatura`, nivel.valor, { shouldDirty: true })}
                  >
                    {nivel.label}
                  </button>
                );
              })}
            </div>
          </div>

          {roles.length > 0 && <RolesPaso control={control} setValue={setValue} nombre={nombre} roles={roles} />}
        </div>
      )}
    </div>
  );
}
