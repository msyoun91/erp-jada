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

const TIPOS = [
  { valor: "tarea", label: "Tarea" },
  { valor: "hilo", label: "Hilo" },
  { valor: "proyecto", label: "Proyecto" },
] as const;

const AYUDA_TIPO: Record<TipoPlantilla, string> = {
  tarea: "Crea una tarea.",
  hilo: "Crea un hilo con pasos encadenados: cada uno se habilita al completar el anterior.",
  proyecto: "Crea un proyecto con sus miembros, sus hilos de pasos y sus tareas sueltas.",
};

type ModoVence = "sin" | "creacion" | "tras_previo";

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
  };
}

function valoresIniciales(p?: PlantillaCompleta): Form {
  if (!p) {
    return {
      nombre: "",
      alcance: "privada",
      tipo: "hilo",
      visibilidad: "privado",
      miembros: [],
      hilos: [],
      pasos: [pasoVacio()],
      disparo_ente: null,
      disparo_estado: null,
    };
  }
  return {
    id: p.id,
    nombre: p.nombre,
    descripcion: p.descripcion ?? undefined,
    alcance: p.alcance,
    tipo: p.tipo,
    visibilidad: p.visibilidad,
    miembros: p.miembros,
    hilos: p.hilos.map((h) => ({
      titulo: h.titulo,
      pasos: p.items.filter((i) => i.hilo_id === h.id).map(pasoDesdeItem),
    })),
    pasos: p.items.filter((i) => !i.hilo_id).map(pasoDesdeItem),
    disparo_ente: p.disparo_ente,
    disparo_estado: p.disparo_estado,
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
  const alcance = useWatch({ control, name: "alcance" }) ?? "privada";
  const miembros = useWatch({ control, name: "miembros" }) ?? [];
  const disparoEnte = useWatch({ control, name: "disparo_ente" }) ?? null;
  // Los que la RLS dejó ver (`getEntes`) y la UI sabe nombrar.
  const entesDisponibles = entes.filter((e) => ENTES[e.codigo]);
  const enteElegido = disparoEnte ? ENTES[disparoEnte] : undefined;
  const datosDelEnte = entes.find((e) => e.codigo === disparoEnte)?.datos ?? [];

  // Cambiar de tipo reacomoda lo cargado en vez de tirarlo: los pasos de un
  // hilo pasan a ser un hilo del proyecto, y al revés se aplanan en orden.
  function cambiarTipo(nuevo: TipoPlantilla) {
    const hilos = getValues("hilos") ?? [];
    const pasos = getValues("pasos") ?? [];
    const todos = [...hilos.flatMap((h) => h.pasos), ...pasos];
    const opciones = { shouldDirty: true };

    if (nuevo === "proyecto") {
      if (tipo === "hilo" && pasos.length > 0) {
        setValue("hilos", [{ titulo: getValues("nombre") || "Hilo", pasos }], opciones);
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

        {(entesDisponibles.length > 0 || enteElegido) && (
          <div>
            <label className="t-label mb-1 block">Cuándo se usa</label>
            <select
              aria-label="Cuándo se usa"
              className="input"
              value={disparoEnte ?? ""}
              onChange={(e) => {
                setValue("disparo_ente", e.target.value || null, { shouldDirty: true });
                setValue("disparo_estado", null, { shouldDirty: true });
              }}
            >
              <option value="">A mano, desde esta vista</option>
              {entesDisponibles.map((e) => (
                <option key={e.codigo} value={e.codigo}>
                  Sola, cuando {ENTES[e.codigo].un} cambia de estado
                </option>
              ))}
            </select>
            {enteElegido && (
              <>
                <select
                  aria-label="Estado que la dispara"
                  className={`input mt-2 ${errors.disparo_estado ? "input-error" : ""}`}
                  {...register("disparo_estado", { setValueAs: (v) => v || null })}
                >
                  <option value="">Elegí el estado…</option>
                  {Object.entries(enteElegido.estados).map(([valor, label]) => (
                    <option key={valor} value={valor}>
                      Cuando pasa a «{label}»
                    </option>
                  ))}
                </select>
                {errors.disparo_estado && <p className="input-error-text">{errors.disparo_estado.message}</p>}
                <p className="t-caption mt-1">
                  Corre para quien cambia el estado, con sus permisos, y solo si la tiene activada:{" "}
                  {alcance === "sistema"
                    ? "cada uno la activa para sí desde Plantillas."
                    : "vos la tenés activada desde que la guardás."}
                  {tipo !== "tarea" && " El hilo o proyecto que crea lleva el nombre de la plantilla."}
                </p>
                {datosDelEnte.length > 0 && (
                  <p className="t-caption mt-1">
                    Podés citar {datosDelEnte.map((d) => `{${d}}`).join(", ")} en el nombre y en los pasos. El texto se
                    copia en la tarea: quien la recibe lo lee aunque no pueda abrir {enteElegido.el}.
                  </p>
                )}
              </>
            )}
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
              nombre="pasos.0"
              etiqueta="Tarea"
              miembros={null}
              puedeTrasPrevio={false}
            />
          </div>
        )}

        {tipo === "hilo" && (
          <ListaPasos
            control={control}
            register={register}
            setValue={setValue}
            nombre="pasos"
            titulo="Pasos"
            ayuda="El orden manda: cada paso se habilita al completar el anterior."
            encadenada
            miembros={null}
            agregar="Agregar paso"
          />
        )}

        {tipo === "proyecto" && (
          <>
            <HilosEditor control={control} register={register} setValue={setValue} miembros={miembros} />
            <ListaPasos
              control={control}
              register={register}
              setValue={setValue}
              nombre="pasos"
              titulo="Tareas sueltas"
              ayuda="Tareas del proyecto que no esperan a nada."
              encadenada={false}
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
};

function HilosEditor({ control, register, setValue, miembros }: Comunes & { miembros: string[] }) {
  const { fields, append, remove, move } = useFieldArray({ control, name: "hilos" });
  const { errors } = useFormState({ control, name: "hilos" });

  return (
    <div>
      <label className="t-label mb-1 block">Hilos</label>
      <p className="t-caption mb-2">Cada hilo es una cadena: sus pasos se habilitan de a uno.</p>
      <div className="flex flex-col gap-3">
        {fields.map((field, h) => (
          <div key={field.id} className="rounded-lg border border-border p-3">
            <div className="mb-3 flex items-center gap-2">
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
              <p className="input-error-text -mt-2 mb-2">{mensajeDe(errors, `hilos.${h}.titulo`)}</p>
            )}
            <ListaPasos
              control={control}
              register={register}
              setValue={setValue}
              nombre={`hilos.${h}.pasos`}
              encadenada
              miembros={miembros}
              agregar="Agregar paso"
            />
          </div>
        ))}
      </div>
      <button
        type="button"
        className="btn btn-ghost btn-sm mt-2"
        onClick={() => append({ titulo: "", pasos: [pasoVacio()] })}
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
  nombre,
  titulo,
  ayuda,
  encadenada,
  miembros,
  agregar,
}: Comunes & {
  nombre: Lista;
  titulo?: string;
  ayuda?: string;
  encadenada: boolean;
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
            nombre={`${nombre}.${i}`}
            etiqueta={encadenada ? `Paso ${i + 1}` : `Tarea ${i + 1}`}
            miembros={miembros}
            puedeTrasPrevio={encadenada && i > 0}
            orden={
              <BotonesOrden
                indice={i}
                total={fields.length}
                onMover={move}
                onQuitar={remove}
                minimo={encadenada ? 1 : 0}
                que={encadenada ? "paso" : "tarea"}
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
  ].join(" · ");

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
        </div>
      )}
    </div>
  );
}
