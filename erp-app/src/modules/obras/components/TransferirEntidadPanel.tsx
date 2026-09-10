"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { contactosExclusivosEmpresa, transferirEmpresa, transferirPersona } from "../actions";
import type { ContactoExclusivo, Usuario } from "../types";

// Transferir cambia el dueño (`creado_por`). Para empresa, la gente que trabaja
// solo en ella puede moverse también — el checklist lo pregunta. El resto queda
// con grant contextual. Persona no tiene cascada.
export function TransferirEntidadPanel({
  tipo,
  id,
  nombre,
  duenioActual,
  usuarios,
  onClose,
}: {
  tipo: "persona" | "empresa";
  id: string;
  nombre: string;
  duenioActual: string | null;
  usuarios: Usuario[];
  onClose: () => void;
}) {
  const [destino, setDestino] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [exclusivos, setExclusivos] = useState<ContactoExclusivo[]>([]);
  const [tildados, setTildados] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (tipo !== "empresa") return;
    contactosExclusivosEmpresa(id).then((r) => {
      setExclusivos(r);
      setTildados(new Set(r.map((c) => c.id)));
    });
  }, [tipo, id]);

  function toggle(cid: string) {
    setTildados((prev) => {
      const next = new Set(prev);
      if (next.has(cid)) next.delete(cid);
      else next.add(cid);
      return next;
    });
  }

  async function transferir() {
    if (!destino) return setError("Elegí a quién transferirla");
    setError(undefined);
    setEnviando(true);
    const result =
      tipo === "persona"
        ? await transferirPersona({ persona_id: id, a_usuario_id: destino })
        : await transferirEmpresa({
            empresa_id: id,
            a_usuario_id: destino,
            personas_exclusivas: [...tildados],
          });
    setEnviando(false);
    if (!result.success) return setError(result.error);
    toast.success(`${tipo === "persona" ? "Persona" : "Empresa"} transferida`);
    onClose();
  }

  return (
    <RightPanel
      title={`Transferir ${tipo}`}
      subtitle={nombre}
      onClose={onClose}
      hayCambios={!!destino}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="button"
            className="btn btn-primary btn-sm"
            onClick={transferir}
            disabled={enviando}
          >
            {enviando ? "Transfiriendo…" : "Transferir"}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
        <p className="t-body-m">
          Dueño actual: <span className="font-semibold">{duenioActual ?? "—"}</span>
        </p>

        <div>
          <label className="t-label t-label-req mb-1 block">Nuevo dueño</label>
          <select
            className={`input ${error ? "input-error" : ""}`}
            value={destino}
            onChange={(e) => setDestino(e.target.value)}
          >
            <option value="">Elegí un usuario…</option>
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
          {error && <p className="input-error-text">{error}</p>}
        </div>

        {tipo === "empresa" && exclusivos.length > 0 && (
          <div>
            <p className="t-label mb-1">Estas personas están solo en esta empresa</p>
            <p className="t-caption mb-2">
              Las tildadas cambian de dueño con la empresa. Las que destildes quedan como están.
            </p>
            <ul className="flex flex-col gap-1">
              {exclusivos.map((c) => (
                <li key={c.id}>
                  <label className="flex items-center gap-2 rounded-md border border-border px-3 py-2">
                    <input
                      type="checkbox"
                      checked={tildados.has(c.id)}
                      onChange={() => toggle(c.id)}
                    />
                    <span className="t-body-m truncate">
                      {c.etiqueta}
                      {c.detalle && <span className="t-caption"> · {c.detalle}</span>}
                    </span>
                  </label>
                </li>
              ))}
            </ul>
          </div>
        )}

        <p className="t-caption">
          El dueño ve la ficha y la edita. Al transferirla, los accesos que vos habías compartido se
          revocan; el nuevo dueño re-comparte si quiere. Queda registrado.
        </p>
      </div>
    </RightPanel>
  );
}
