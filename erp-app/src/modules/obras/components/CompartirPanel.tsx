"use client";

import { useState } from "react";
import { X } from "lucide-react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import {
  compartirEmpresa,
  compartirPersona,
  revocarEmpresa,
  revocarPersona,
} from "../actions";
import type { Compartido, Usuario } from "../types";

// Compartir es acto del dueño: da lectura de la ficha (contacto incluido, vía
// obras_ficha_persona que registra). Revocable. No se re-comparte.
export function CompartirPanel({
  tipo,
  id,
  nombre,
  compartidos,
  usuarios,
  onClose,
}: {
  tipo: "persona" | "empresa";
  id: string;
  nombre: string;
  compartidos: Compartido[];
  usuarios: Usuario[];
  onClose: () => void;
}) {
  const [destino, setDestino] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  const yaCompartida = new Set(compartidos.map((c) => c.usuario_id));
  const disponibles = usuarios.filter((u) => !yaCompartida.has(u.id));

  async function compartir() {
    if (!destino) return setError("Elegí con quién compartirla");
    setError(undefined);
    setEnviando(true);
    const result =
      tipo === "persona"
        ? await compartirPersona({ id, usuario_id: destino })
        : await compartirEmpresa({ id, usuario_id: destino });
    setEnviando(false);
    if (!result.success) return setError(result.error);
    toast.success("Compartida");
    setDestino("");
  }

  async function revocar(usuarioId: string) {
    const result =
      tipo === "persona" ? await revocarPersona(id, usuarioId) : await revocarEmpresa(id, usuarioId);
    if (!result.success) return toast.error(result.error);
    toast.success("Acceso revocado");
  }

  return (
    <RightPanel
      title={`Compartir ${tipo}`}
      subtitle={nombre}
      onClose={onClose}
      hayCambios={false}
      footer={
        <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
          Cerrar
        </button>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
        <div>
          <label className="t-label mb-1 block">Compartir con</label>
          <div className="flex gap-2">
            <select
              className={`input ${error ? "input-error" : ""}`}
              value={destino}
              onChange={(e) => setDestino(e.target.value)}
            >
              <option value="">Elegí un usuario…</option>
              {disponibles.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="btn btn-primary btn-sm shrink-0"
              onClick={compartir}
              disabled={enviando}
            >
              {enviando ? "…" : "Compartir"}
            </button>
          </div>
          {error && <p className="input-error-text">{error}</p>}
        </div>

        {compartidos.length > 0 && (
          <div>
            <p className="t-label mb-1">Compartida con</p>
            <ul className="flex flex-col gap-1">
              {compartidos.map((c) => (
                <li
                  key={c.usuario_id}
                  className="flex items-center justify-between rounded-md border border-border px-3 py-2"
                >
                  <span className="t-body-m truncate">{c.usuario}</span>
                  <button
                    type="button"
                    className="btn-ghost text-tertiary tap-target"
                    aria-label={`Revocar acceso de ${c.usuario}`}
                    onClick={() => revocar(c.usuario_id)}
                  >
                    <X size={16} strokeWidth={1.75} />
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )}

        <p className="t-caption">
          Quien recibe la ficha la ve completa —contacto incluido, y cada vista queda registrada—.
          No puede editarla ni re-compartirla. Podés revocar el acceso cuando quieras.
        </p>
      </div>
    </RightPanel>
  );
}
