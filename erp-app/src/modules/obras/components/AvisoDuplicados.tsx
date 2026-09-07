"use client";

import { AlertTriangle } from "lucide-react";
import type { DuplicadoEmpresa, DuplicadoObra, DuplicadoPersona } from "../types";

// Advertencia, nunca bloqueo: el usuario decide si es la misma o no.
function Marco({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex gap-2 rounded-md border border-warning/20 bg-warning-bg px-3 py-2 text-warning-text">
      <AlertTriangle size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}

// De una obra ajena solo llega el responsable: ni dirección, ni estado, ni
// link. Alcanza para ir a preguntar sin exponer la cartera del otro.
export function AvisoDuplicadosObra({ duplicados }: { duplicados: DuplicadoObra[] }) {
  if (duplicados.length === 0) return null;

  return (
    <Marco>
      <p className="t-body-m font-semibold">Puede que esta obra ya esté cargada</p>
      <ul className="t-caption mt-1 flex flex-col gap-1">
        {duplicados.map((d, i) => (
          <li key={d.obra_id ?? i}>
            {d.es_mia ? (
              <>
                <span className="font-semibold">{d.nombre}</span>
                {d.localidad && ` · ${d.localidad}`} — es tuya
              </>
            ) : (
              <>Una obra parecida está cargada por {d.responsable}. Consultale antes de duplicarla.</>
            )}
          </li>
        ))}
      </ul>
    </Marco>
  );
}

export function AvisoDuplicadosEmpresa({
  duplicados,
  onUsar,
}: {
  duplicados: DuplicadoEmpresa[];
  onUsar?: (id: string) => void;
}) {
  if (duplicados.length === 0) return null;

  return (
    <Marco>
      <p className="t-body-m font-semibold">Empresas parecidas ya cargadas</p>
      <ul className="t-caption mt-1 flex flex-col gap-1">
        {duplicados.map((d) => (
          <li key={d.empresa_id} className="flex flex-wrap items-center gap-2">
            <span className="font-semibold">{d.razon_social}</span>
            {d.localidad && <span>· {d.localidad}</span>}
            {onUsar && (
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => onUsar(d.empresa_id)}>
                Usar esta
              </button>
            )}
          </li>
        ))}
      </ul>
    </Marco>
  );
}

// Identidad mínima: nombre, apellido y empresa. Nunca teléfono ni email — el
// contacto sale solo por la ficha, que deja registro.
export function AvisoDuplicadosPersona({
  duplicados,
  onUsar,
}: {
  duplicados: DuplicadoPersona[];
  onUsar?: (id: string) => void;
}) {
  if (duplicados.length === 0) return null;

  return (
    <Marco>
      <p className="t-body-m font-semibold">Personas parecidas ya cargadas</p>
      <ul className="t-caption mt-1 flex flex-col gap-1">
        {duplicados.map((d) => (
          <li key={d.persona_id} className="flex flex-wrap items-center gap-2">
            <span className="font-semibold">
              {d.nombre} {d.apellido ?? ""}
            </span>
            {d.empresa && <span>· {d.empresa}</span>}
            {d.coincide !== "nombre" && <span>· coincide el {d.coincide}</span>}
            {onUsar && (
              <button type="button" className="btn btn-ghost btn-sm" onClick={() => onUsar(d.persona_id)}>
                Usar esta
              </button>
            )}
          </li>
        ))}
      </ul>
    </Marco>
  );
}
