"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "./RightPanel";
import { compartirRegistros, type FilaSinAcceso } from "@/lib/accesos";
import { mensajeError } from "@/lib/utils";
import { ENTES } from "@/lib/entes";

type Verbo = "guardar" | "relacionar";

function clave(f: FilaSinAcceso) {
  return `${f.usuario_id}:${f.ente}:${f.registro_id}`;
}

function aviso(filas: FilaSinAcceso[]): string | null {
  if (filas.length === 0) return null;
  const nombres = [...new Set(filas.map((f) => f.usuario))];
  return `No quedan asignados: ${nombres.join(", ")} — no pueden abrir lo relacionado.`;
}

// Antes de guardar o relacionar, si alguien va a quedar afuera (sql/062,
// sql/063), un panel ofrece compartir lo que es tuyo. Cerrarlo es no
// compartir — salvo cuando quien actúa no tiene permiso para sacar a nadie de
// la tarea (`puedeDejarAfuera: false`): ahí no hay salida sin compartir.
export function useConfirmarAcceso({
  verbo,
  puedeDejarAfuera,
}: {
  verbo: Verbo;
  puedeDejarAfuera: boolean;
}) {
  const [estado, setEstado] = useState<{
    filas: FilaSinAcceso[];
    seguir: (aviso: string | null) => Promise<void>;
  } | null>(null);

  async function confirmarAcceso(
    filas: FilaSinAcceso[],
    seguir: (aviso: string | null) => Promise<void>,
  ) {
    if (filas.length === 0) {
      await seguir(null);
      return;
    }
    if (!puedeDejarAfuera && filas.some((f) => !f.compartible)) {
      toast.error(mensajeError({ code: "TA016" }));
      return;
    }
    setEstado({ filas, seguir });
  }

  const panelAcceso = estado && (
    <CompartirAccesoPanel
      verbo={verbo}
      puedeDejarAfuera={puedeDejarAfuera}
      filas={estado.filas}
      onCancelar={() => setEstado(null)}
      onResuelto={async (avisoTexto) => {
        const { seguir } = estado;
        setEstado(null);
        await seguir(avisoTexto);
      }}
    />
  );

  return { confirmarAcceso, panelAcceso };
}

function CompartirAccesoPanel({
  verbo,
  puedeDejarAfuera,
  filas,
  onCancelar,
  onResuelto,
}: {
  verbo: Verbo;
  puedeDejarAfuera: boolean;
  filas: FilaSinAcceso[];
  onCancelar: () => void;
  onResuelto: (aviso: string | null) => Promise<void>;
}) {
  const [tildadas, setTildadas] = useState<Set<string>>(
    () => new Set(filas.filter((f) => f.compartible).map(clave)),
  );
  const [enviando, setEnviando] = useState(false);

  function toggle(f: FilaSinAcceso) {
    setTildadas((prev) => {
      const next = new Set(prev);
      const k = clave(f);
      if (next.has(k)) next.delete(k);
      else next.add(k);
      return next;
    });
  }

  async function compartirYSeguir() {
    setEnviando(true);
    const seleccion = filas
      .filter((f) => tildadas.has(clave(f)))
      .map((f) => ({ usuario_id: f.usuario_id, ente: f.ente, registro_id: f.registro_id }));
    const result = await compartirRegistros(seleccion);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    await onResuelto(aviso(filas.filter((f) => !tildadas.has(clave(f)))));
  }

  async function seguirSinCompartir() {
    await onResuelto(aviso(filas));
  }

  const porUsuario = new Map<string, FilaSinAcceso[]>();
  for (const f of filas) {
    porUsuario.set(f.usuario, [...(porUsuario.get(f.usuario) ?? []), f]);
  }

  const faltaTildar = !puedeDejarAfuera && filas.some((f) => !tildadas.has(clave(f)));

  return (
    <RightPanel
      title={`Antes de ${verbo}`}
      onClose={puedeDejarAfuera ? seguirSinCompartir : onCancelar}
      hayCambios={false}
      footer={
        <>
          {puedeDejarAfuera && (
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={seguirSinCompartir}
              disabled={enviando}
            >
              {verbo[0].toUpperCase()}
              {verbo.slice(1)} sin compartir
            </button>
          )}
          <button
            type="button"
            className="btn btn-primary btn-sm"
            onClick={compartirYSeguir}
            disabled={enviando || faltaTildar}
          >
            {enviando ? "…" : `Compartir y ${verbo}`}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto px-5 py-4">
        <p className="t-caption">
          Quien no pueda abrir lo relacionado no queda asignado. Compartir da lectura y se revoca
          desde la ficha.
        </p>
        {[...porUsuario.entries()].map(([usuario, filasUsuario]) => (
          <div key={usuario}>
            <p className="t-label mb-1">{usuario} no puede abrir:</p>
            <ul className="flex flex-col gap-1">
              {filasUsuario.map((f) => (
                <li key={clave(f)}>
                  <label className="tap-target flex items-center gap-2 rounded-md border border-border px-3 py-2">
                    <input
                      type="checkbox"
                      checked={tildadas.has(clave(f))}
                      disabled={!f.compartible}
                      onChange={() => toggle(f)}
                    />
                    {f.compartible ? (
                      <span className="t-body-m truncate">
                        {ENTES[f.ente]?.nombre ?? f.ente} {f.etiqueta}
                      </span>
                    ) : (
                      <span className="t-body-m truncate text-text-tertiary">
                        {f.etiqueta === null ? "Algo relacionado que no podés ver" : "No lo podés compartir"}
                      </span>
                    )}
                  </label>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </RightPanel>
  );
}
