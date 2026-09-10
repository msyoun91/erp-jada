"use client";

import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { RightPanel } from "@/components/ui/RightPanel";
import {
  compartirEmpresa,
  compartirObra,
  compartirPersona,
  contarVinculosReceptor,
  relacionesCompartiblesEmpresa,
  relacionesCompartiblesObra,
  revocarEmpresa,
  revocarObra,
  revocarPersona,
} from "../actions";
import type { Compartido, RelacionCompartible, Usuario } from "../types";

type Tipo = "obra" | "empresa" | "persona";

// Compartir es acto del dueño: da lectura de la ficha, revocable, no se
// re-comparte. Obra y empresa además ofrecen un checklist de lo vinculado que
// es mío para compartirlo en el mismo acto; persona va sola.
export function CompartirPanel({
  tipo,
  id,
  nombre,
  compartidos,
  usuarios,
  onClose,
}: {
  tipo: Tipo;
  id: string;
  nombre: string;
  compartidos: Compartido[];
  usuarios: Usuario[];
  onClose: () => void;
}) {
  const [destino, setDestino] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();
  const [relaciones, setRelaciones] = useState<RelacionCompartible[]>([]);
  const [tildadas, setTildadas] = useState<Set<string>>(new Set());
  const [revocando, setRevocando] = useState<{ usuarioId: string; usuario: string; n: number } | null>(
    null,
  );

  const yaCompartida = new Set(compartidos.map((c) => c.usuario_id));
  const editando = yaCompartida.has(destino);
  const conChecklist = tipo === "obra" || tipo === "empresa";

  // El checklist depende del destino: marca lo que ese usuario ya tiene. Sin
  // reset síncrono — si no hay destino el bloque no se renderiza igual, y el
  // `cancelado` evita que una respuesta vieja pise a la nueva.
  useEffect(() => {
    if (!conChecklist || !destino) return;
    let cancelado = false;
    const cargar =
      tipo === "obra"
        ? relacionesCompartiblesObra(id, destino)
        : relacionesCompartiblesEmpresa(id, destino);
    cargar.then((r) => {
      if (cancelado) return;
      setRelaciones(r);
      setTildadas(new Set(r.filter((x) => x.ya_compartida).map((x) => x.id)));
    });
    return () => {
      cancelado = true;
    };
  }, [conChecklist, tipo, id, destino]);

  function toggle(relId: string) {
    setTildadas((prev) => {
      const next = new Set(prev);
      if (next.has(relId)) next.delete(relId);
      else next.add(relId);
      return next;
    });
  }

  async function compartir() {
    if (!destino) return setError("Elegí con quién compartirla");
    setError(undefined);
    setEnviando(true);

    const seleccion = [...tildadas];
    let result;
    if (tipo === "obra") {
      result = await compartirObra({
        id,
        usuario_id: destino,
        empresas: relaciones.filter((r) => r.tipo === "empresa" && tildadas.has(r.id)).map((r) => r.id),
        personas: relaciones.filter((r) => r.tipo === "persona" && tildadas.has(r.id)).map((r) => r.id),
      });
    } else if (tipo === "empresa") {
      result = await compartirEmpresa({ id, usuario_id: destino, personas: seleccion });
    } else {
      result = await compartirPersona({ id, usuario_id: destino });
    }

    setEnviando(false);
    if (!result.success) return setError(result.error);
    toast.success(editando ? "Cambios guardados" : "Compartida");
  }

  // Al revocar una obra, los vínculos que el receptor le agregó con contactos
  // suyos se desactivan (obras_revocar_obra). Se avisa antes si hay alguno.
  async function pedirRevocar(usuarioId: string, usuario: string) {
    const n = tipo === "obra" ? await contarVinculosReceptor(id, usuarioId) : 0;
    if (n > 0) setRevocando({ usuarioId, usuario, n });
    else revocar(usuarioId);
  }

  async function revocar(usuarioId: string) {
    const result =
      tipo === "obra"
        ? await revocarObra(id, usuarioId)
        : tipo === "empresa"
          ? await revocarEmpresa(id, usuarioId)
          : await revocarPersona(id, usuarioId);
    setRevocando(null);
    if (!result.success) return toast.error(result.error);
    toast.success("Acceso revocado");
  }

  return (
    <>
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
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre}
                  {yaCompartida.has(u.id) ? " · ya compartida" : ""}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="btn btn-primary btn-sm shrink-0"
              onClick={compartir}
              disabled={enviando}
            >
              {enviando ? "…" : editando ? "Guardar" : "Compartir"}
            </button>
          </div>
          {editando && (
            <p className="t-caption mt-1">
              Ya compartida con esta persona. Ajustá el reparto y guardá.
            </p>
          )}
          {error && <p className="input-error-text">{error}</p>}
        </div>

        {conChecklist && destino && relaciones.length > 0 && (
          <div>
            <p className="t-label mb-1">Compartir también</p>
            <p className="t-caption mb-2">
              Lo vinculado a {tipo === "obra" ? "esta obra" : "esta empresa"} que cargaste vos.
              Tildado se comparte; destildado se deja de compartir. Todo se revoca junto con{" "}
              {tipo === "obra" ? "la obra" : "la empresa"}.
            </p>
            <ul className="flex flex-col gap-1">
              {relaciones.map((r) => (
                <li key={r.id}>
                  <label className="flex items-center gap-2 rounded-md border border-border px-3 py-2">
                    <input type="checkbox" checked={tildadas.has(r.id)} onChange={() => toggle(r.id)} />
                    <span className="t-body-m truncate">
                      {r.etiqueta}
                      <span className="t-caption"> · {r.tipo}</span>
                      {r.detalle && <span className="t-caption"> · {r.detalle}</span>}
                    </span>
                  </label>
                </li>
              ))}
            </ul>
          </div>
        )}

        {compartidos.length > 0 && (
          <div>
            <p className="t-label mb-1">Compartida con</p>
            <ul className="flex flex-col gap-1">
              {compartidos.map((c) => (
                <li
                  key={c.usuario_id}
                  className="flex items-center justify-between rounded-md border border-border px-3 py-2"
                >
                  {conChecklist ? (
                    <button
                      type="button"
                      className="t-body-m min-w-0 flex-1 truncate text-left hover:underline"
                      onClick={() => setDestino(c.usuario_id)}
                    >
                      {c.usuario}
                    </button>
                  ) : (
                    <span className="t-body-m truncate">{c.usuario}</span>
                  )}
                  <button
                    type="button"
                    className="btn-ghost text-tertiary tap-target"
                    aria-label={`Revocar acceso de ${c.usuario}`}
                    onClick={() => pedirRevocar(c.usuario_id, c.usuario)}
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

    {revocando && (
      <ConfirmModal
        title="Revocar acceso"
        mensaje={`«${revocando.usuario}» agregó ${revocando.n} ${
          revocando.n === 1 ? "vínculo" : "vínculos"
        } a esta obra con contactos suyos. Al revocar, esos vínculos se desactivan.`}
        confirmLabel="Revocar"
        onConfirm={async () => {
          await revocar(revocando.usuarioId);
        }}
        onClose={() => setRevocando(null)}
      />
    )}
    </>
  );
}
