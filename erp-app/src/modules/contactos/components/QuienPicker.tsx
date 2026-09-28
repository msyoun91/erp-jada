"use client";

import { useEffect, useState } from "react";
import { buscarParecidas } from "../actions";
import type { ParecidaAviso } from "../types";
import { BuscadorVinculables, IconoContacto, type TipoContacto } from "./Buscador";
import { AvisoParecidas } from "./Parecidas";

export type QuienElegido = { tipo: TipoContacto; id: string | null; nombre: string; telefono: string; email: string };

// "¿Quién?" del alta de una obra con origen referente: uno existente o uno
// nuevo (`id` null), sin el campo empresa — ya es el nivel anidado. Lo compone
// `app/`; el alta lo guarda con la obra, todo o nada.
export function QuienPicker({
  valor,
  onCambio,
}: {
  valor: QuienElegido | null;
  onCambio: (q: QuienElegido | null) => void;
}) {
  if (!valor) {
    return (
      <BuscadorVinculables
        onElegir={(v) => onCambio({ tipo: v.tipo as TipoContacto, id: v.id, nombre: v.nombre, telefono: "", email: "" })}
        onCrear={(tipo, nombre) => onCambio({ tipo, id: null, nombre, telefono: "", email: "" })}
      />
    );
  }

  if (valor.id) {
    return (
      <div className="flex items-center gap-2 rounded-md border border-border px-3 py-2">
        <IconoContacto tipo={valor.tipo} />
        <span className="t-body-m min-w-0 flex-1 truncate">{valor.nombre}</span>
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onCambio(null)}>
          Cambiar
        </button>
      </div>
    );
  }

  return <QuienNuevo valor={valor} onCambio={onCambio} />;
}

// El aviso a ciegas, mientras escribe: el alta de la obra guarda al nuevo, y
// si se parece queda congelado con ella.
function QuienNuevo({ valor, onCambio }: { valor: QuienElegido; onCambio: (q: QuienElegido | null) => void }) {
  const [parecidas, setParecidas] = useState<ParecidaAviso[]>([]);
  const { tipo, nombre, telefono, email } = valor;

  useEffect(() => {
    let vigente = true;
    const t = setTimeout(async () => {
      const r = nombre.trim() ? await buscarParecidas({ tipo, nombre, telefono, email }) : null;
      if (vigente) setParecidas(r?.success ? r.resultados : []);
    }, 400);
    return () => {
      vigente = false;
      clearTimeout(t);
    };
  }, [tipo, nombre, telefono, email]);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-border p-3">
      <div className="flex items-center gap-2">
        <IconoContacto tipo={valor.tipo} />
        <p className="t-label flex-1">{valor.tipo === "persona" ? "Persona nueva" : "Empresa nueva"}</p>
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onCambio(null)}>
          Cambiar
        </button>
      </div>
      <input
        aria-label="Nombre"
        className="input"
        value={valor.nombre}
        onChange={(e) => onCambio({ ...valor, nombre: e.target.value })}
      />
      <input
        aria-label="Teléfono"
        type="tel"
        placeholder="Teléfono"
        className="input"
        value={valor.telefono}
        onChange={(e) => onCambio({ ...valor, telefono: e.target.value })}
      />
      <input
        aria-label="Email"
        type="email"
        placeholder="Email"
        className="input"
        value={valor.email}
        onChange={(e) => onCambio({ ...valor, email: e.target.value })}
      />
      {parecidas.length > 0 && (
        <AvisoParecidas
          tipo={tipo}
          items={parecidas}
          verbo="crealo"
          usar="Elegir esa"
          onUsar={(p) => onCambio({ tipo, id: p.id, nombre: p.nombre, telefono: "", email: "" })}
        />
      )}
    </div>
  );
}
