"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { EyeOff } from "lucide-react";
import { toast } from "sonner";
import { formatFechaHora } from "@/lib/utils";
import { agregarNota, ocultarNota } from "../actions";
import { notaSchema, type Nota, type NotaForm } from "../types";
import { useNombre, useTareas } from "./contexto";

// Anota quien ve el hilo, también en lo cerrado: es la forma de corregir lo
// congelado. Solo se agregan; el admin las oculta.
export function NotasSection({ hiloId, tareaId, notas }: { hiloId: string; tareaId: string | null; notas: Nota[] }) {
  const { admin } = useTareas();
  const nombre = useNombre();
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<NotaForm>({
    resolver: zodResolver(notaSchema),
    defaultValues: { hilo_id: hiloId, tarea_id: tareaId, texto: "" },
  });

  async function onSubmit(data: NotaForm) {
    setEnviando(true);
    const result = await agregarNota(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    reset();
  }

  async function onOcultar(id: string) {
    const result = await ocultarNota(id);
    if (!result.success) toast.error(result.error);
    else toast.success("Nota oculta");
  }

  return (
    <div className="flex flex-col gap-3">
      {notas.length === 0 && <p className="t-caption">Sin notas.</p>}
      {notas.map((n) => (
        <div key={n.id} className={`rounded-md border border-border p-3 ${n.activo ? "" : "bg-bg-subtle"}`}>
          <div className="t-caption mb-1 flex items-center gap-2">
            <span className="font-semibold text-text-secondary">{nombre(n.autor_id)}</span>
            <span>{formatFechaHora(n.created_at)}</span>
            {!n.activo && <span className="badge badge-neutral">Oculta · {nombre(n.ocultada_por)}</span>}
            <div className="flex-1" />
            {admin && n.activo && (
              <button className="icon-btn h-7 w-7" onClick={() => onOcultar(n.id)} aria-label="Ocultar nota" title="Ocultar">
                <EyeOff size={14} strokeWidth={1.75} />
              </button>
            )}
          </div>
          <p className="t-body-m whitespace-pre-wrap">{n.texto}</p>
        </div>
      ))}

      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-2">
        <textarea
          rows={2}
          placeholder="Agregar una nota…"
          aria-label="Nota"
          className={`input ${errors.texto ? "input-error" : ""}`}
          {...register("texto")}
        />
        {errors.texto && <p className="input-error-text">{errors.texto.message}</p>}
        <button type="submit" className="btn btn-secondary btn-sm self-end" disabled={enviando}>
          {enviando ? "Guardando…" : "Agregar nota"}
        </button>
      </form>
    </div>
  );
}
