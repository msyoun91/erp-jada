"use client";

import type { CandidatoTransferencia, EstadoTransferencia } from "../types";

// Los tres estados de sql/087, uno por contacto. El default es `va`: cambia de
// dueño y el saliente lo sigue viendo donde ya lo tenía — el no destructivo.
// `saco` solo se ofrece si hay algo del saliente de dónde sacarlo.
export function estadosIniciales(candidatos: CandidatoTransferencia[]) {
  return new Map<string, EstadoTransferencia>(candidatos.map((c) => [c.id, "va"]));
}

export function tieneVinculosPropios(c: CandidatoTransferencia) {
  return c.vinculos.some((v) => v.mio);
}

export function ChecklistTransferencia({
  candidatos,
  estados,
  onCambio,
}: {
  candidatos: CandidatoTransferencia[];
  estados: Map<string, EstadoTransferencia>;
  onCambio: (estados: Map<string, EstadoTransferencia>) => void;
}) {
  // Cambiar una empresa arrastra a su gente: mover una empresa de 12 personas
  // serían 13 clicks. Cada fila sigue siendo editable después.
  function cambiar(candidato: CandidatoTransferencia, estado: EstadoTransferencia) {
    const next = new Map(estados);
    next.set(candidato.id, estado);

    if (candidato.tipo === "empresa") {
      for (const otro of candidatos) {
        if (otro.tipo !== "persona") continue;
        const pertenece =
          otro.via_empresa_id === candidato.id ||
          otro.vinculos.some((v) => v.tipo === "empresa" && v.id === candidato.id);
        if (pertenece) next.set(otro.id, estado);
      }
    }

    onCambio(next);
  }

  return (
    <ul className="flex flex-col gap-2">
      {candidatos.map((c) => {
        const propios = c.vinculos.filter((v) => v.mio);
        const ajenos = c.vinculos.filter((v) => !v.mio);
        const estado = estados.get(c.id) ?? "va";

        return (
          <li key={c.id} className="rounded-md border border-border px-3 py-2">
            <p className="t-body-m truncate font-medium">
              {c.etiqueta}
              <span className="t-caption">
                {" · "}
                {c.tipo === "empresa" ? "empresa" : "persona"}
                {c.origen === "via_empresa" && " · por su empresa"}
                {c.detalle && ` · ${c.detalle}`}
              </span>
            </p>

            <div className="mt-2 flex flex-col gap-1">
              <Opcion
                nombre={`estado-${c.id}`}
                activo={estado === "queda"}
                onClick={() => cambiar(c, "queda")}
                texto="No se va"
                nota="Queda tuya; el nuevo dueño la ve solo dentro de esta ficha"
              />
              <Opcion
                nombre={`estado-${c.id}`}
                activo={estado === "va"}
                onClick={() => cambiar(c, "va")}
                texto="Se va"
                nota={
                  propios.length > 0
                    ? `La seguís viendo en ${propios.map((v) => v.etiqueta).join(" · ")}`
                    : "Cambia de dueño"
                }
              />
              {propios.length > 0 && (
                <Opcion
                  nombre={`estado-${c.id}`}
                  activo={estado === "saco"}
                  onClick={() => cambiar(c, "saco")}
                  texto="Se va, y la saco"
                  nota={`Dejás de verla: se desvincula de ${propios.map((v) => v.etiqueta).join(" · ")}`}
                  peligro
                />
              )}
            </div>

            {ajenos.length > 0 && (
              <p className="t-caption mt-2">
                En fichas de otros: {ajenos.map((v) => v.etiqueta).join(" · ")} — no se tocan
              </p>
            )}
          </li>
        );
      })}
    </ul>
  );
}

function Opcion({
  nombre,
  activo,
  onClick,
  texto,
  nota,
  peligro,
}: {
  nombre: string;
  activo: boolean;
  onClick: () => void;
  texto: string;
  nota: string;
  peligro?: boolean;
}) {
  return (
    <label className="flex cursor-pointer items-start gap-2">
      <input
        type="radio"
        name={nombre}
        checked={activo}
        onChange={onClick}
        className="mt-0.5 shrink-0"
      />
      <span className="min-w-0">
        <span className={`t-body-s ${peligro && activo ? "text-danger font-medium" : ""}`}>
          {texto}
        </span>
        <span className="t-caption block">{nota}</span>
      </span>
    </label>
  );
}
