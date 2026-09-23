"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { asignarEquipo } from "../actions";
import type { Equipo, Usuario } from "../types";

export function AgregarMiembroPanel({
  equipo,
  candidatos,
  onClose,
}: {
  equipo: Equipo;
  candidatos: { usuario: Usuario; equipoActual: string | undefined }[];
  onClose: () => void;
}) {
  const [usuarioId, setUsuarioId] = useState("");
  const [enviando, setEnviando] = useState(false);

  const elegido = candidatos.find((c) => c.usuario.id === usuarioId);

  async function guardar() {
    setEnviando(true);
    const result = await asignarEquipo({ usuario_id: usuarioId, equipo_id: equipo.id });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(`${elegido?.usuario.nombre} se sumó a ${equipo.nombre}`);
    onClose();
  }

  return (
    <RightPanel
      title="Agregar miembro"
      subtitle={equipo.nombre}
      onClose={onClose}
      hayCambios={usuarioId !== ""}
      footer={
        <>
          <div className="flex-1" />
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={onClose}
            disabled={enviando}
          >
            Cancelar
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={guardar}
            disabled={enviando || !usuarioId}
          >
            {enviando ? "Agregando…" : "Agregar"}
          </button>
        </>
      }
    >
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        {candidatos.length === 0 ? (
          <p className="t-body-m">
            No hay usuarios activos para sumar. Quien administra usuarios no puede ser miembro de
            un equipo.
          </p>
        ) : (
          <div>
            <label htmlFor="miembro-usuario" className="t-label t-label-req mb-1 block">
              Usuario
            </label>
            <select
              id="miembro-usuario"
              className="input"
              value={usuarioId}
              onChange={(e) => setUsuarioId(e.target.value)}
            >
              <option value="">— seleccionar —</option>
              {candidatos.map(({ usuario, equipoActual }) => (
                <option key={usuario.id} value={usuario.id}>
                  {usuario.nombre}
                  {equipoActual ? ` (en ${equipoActual})` : ""}
                </option>
              ))}
            </select>
            {elegido?.equipoActual && (
              <p className="t-caption mt-1">
                Sale de {elegido.equipoActual} y pierde lo que le dio su delegador. Lo que le
                asignaste vos se queda.
              </p>
            )}
          </div>
        )}
      </div>
    </RightPanel>
  );
}
