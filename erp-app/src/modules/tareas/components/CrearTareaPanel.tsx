"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearHilo, crearTarea } from "../actions";
import { crearTareaSchema, type CrearTareaForm, type TareaHilo } from "../types";
import { HiloBuscador } from "./HiloBuscador";
import { RecurrenciaFields, type RecurrenciaValue } from "./RecurrenciaFields";

type ModoHilo = "ninguno" | "existente" | "nuevo";

function manana(): string {
  const d = new Date();
  d.setDate(d.getDate() + 1);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function CrearTareaPanel({
  usuarioActualId,
  usuarios,
  hilos,
  hiloFijo,
  puedeAsignar,
  onClose,
}: {
  usuarioActualId: string;
  usuarios: { id: string; nombre: string }[];
  hilos: TareaHilo[];
  hiloFijo?: { id: string; titulo: string };
  puedeAsignar: boolean;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const [modoHilo, setModoHilo] = useState<ModoHilo>("ninguno");
  const [hiloExistenteId, setHiloExistenteId] = useState("");
  const [hiloNuevoTitulo, setHiloNuevoTitulo] = useState("");
  const [hiloCreadoId, setHiloCreadoId] = useState<string | null>(null);
  const [recurrencia, setRecurrencia] = useState<RecurrenciaValue>({
    recurrencia_activa: false,
    recurrencia_una_vez: false,
    recurrencia_intervalo: "mes",
    recurrencia_cada: 1,
    recurrencia_proxima: "",
  });
  const tareaSerSuelta = !hiloFijo && modoHilo === "ninguno";

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<CrearTareaForm>({
    resolver: zodResolver(crearTareaSchema),
    defaultValues: { asignado_a: usuarioActualId, fecha_vencimiento: manana() },
  });

  async function onSubmit(data: CrearTareaForm) {
    if (!hiloFijo && modoHilo === "existente" && !hiloExistenteId) {
      toast.error("Elegí un hilo");
      return;
    }
    if (!hiloFijo && modoHilo === "nuevo" && !hiloNuevoTitulo.trim()) {
      toast.error("El título del hilo es obligatorio");
      return;
    }
    if (tareaSerSuelta && recurrencia.recurrencia_activa && !recurrencia.recurrencia_proxima) {
      toast.error("Elegí la próxima fecha de repetición");
      return;
    }

    setEnviando(true);

    let hilo_id: string | undefined = hiloFijo?.id;
    if (!hiloFijo && modoHilo === "existente") {
      hilo_id = hiloExistenteId;
    } else if (!hiloFijo && modoHilo === "nuevo") {
      if (hiloCreadoId) {
        hilo_id = hiloCreadoId;
      } else {
        const resultHilo = await crearHilo({ titulo: hiloNuevoTitulo });
        if (!resultHilo.success) {
          setEnviando(false);
          toast.error(resultHilo.error);
          return;
        }
        hilo_id = resultHilo.hilo_id;
        setHiloCreadoId(resultHilo.hilo_id);
      }
    }

    const result = await crearTarea({
      ...data,
      hilo_id,
      ...(tareaSerSuelta ? recurrencia : {}),
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea creada");
    onClose();
  }

  return (
    <RightPanel
      title="Nueva tarea"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="crear-tarea-form" className="btn btn-primary" disabled={enviando}>
            {enviando ? "Creando..." : "Crear tarea"}
          </button>
        </>
      }
    >
      <form
        id="crear-tarea-form"
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label mb-1 block">Título</label>
          <input className={`input ${errors.titulo ? "input-error" : ""}`} {...register("titulo")} />
          {errors.titulo && <p className="input-error-text">{errors.titulo.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea className="input" rows={3} {...register("descripcion")} />
        </div>

        {puedeAsignar && (
          <div>
            <label className="t-label mb-1 block">Asignar a</label>
            <select className="input" {...register("asignado_a")}>
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.id === usuarioActualId ? `${u.nombre} (vos)` : u.nombre}
                </option>
              ))}
            </select>
          </div>
        )}

        <div>
          <label className="t-label mb-1 block">Vencimiento</label>
          <input type="date" className="input" {...register("fecha_vencimiento")} />
        </div>

        <div className="border-t border-border pt-4">
          <label className="t-label mb-2 block">Hilo</label>
          {hiloFijo ? (
            <p className="t-body-m text-text-primary">{hiloFijo.titulo}</p>
          ) : (
            <>
              <select
                className="input"
                value={modoHilo}
                onChange={(e) => {
                  setModoHilo(e.target.value as ModoHilo);
                  setHiloExistenteId("");
                }}
              >
                <option value="ninguno">Tarea suelta, sin hilo</option>
                <option value="existente">Agregar a hilo existente</option>
                <option value="nuevo">Crear hilo nuevo</option>
              </select>

              {modoHilo === "existente" && (
                <div className="mt-2">
                  <HiloBuscador hilos={hilos} value={hiloExistenteId} onChange={setHiloExistenteId} />
                </div>
              )}

              {modoHilo === "nuevo" && (
                <input
                  className="input mt-2"
                  placeholder="Título del hilo"
                  value={hiloNuevoTitulo}
                  onChange={(e) => setHiloNuevoTitulo(e.target.value)}
                />
              )}
            </>
          )}
        </div>

        {tareaSerSuelta && (
          <div className="border-t border-border pt-4">
            <RecurrenciaFields value={recurrencia} onChange={setRecurrencia} />
          </div>
        )}
      </form>
    </RightPanel>
  );
}
