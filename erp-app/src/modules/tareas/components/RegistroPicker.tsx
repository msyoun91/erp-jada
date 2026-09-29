"use client";

import { useEffect, useState } from "react";
import { X } from "lucide-react";
import { toast } from "sonner";
import { SearchInput } from "@/components/ui/SearchInput";
import { buscarRegistrosDe } from "../actions";
import type { RegistroEncontrado } from "../types";

// El registro de "Sobre" al usar una plantilla: solo ese ente y lo que quien
// la usa ve (`buscar_registros`).
export function RegistroPicker({
  ente,
  placeholder,
  elegido,
  onElegir,
}: {
  ente: string;
  placeholder: string;
  elegido: RegistroEncontrado | null;
  onElegir: (r: RegistroEncontrado | null) => void;
}) {
  const [texto, setTexto] = useState("");
  const [resultado, setResultado] = useState<{ clave: string; registros: RegistroEncontrado[] } | null>(null);
  const clave = texto.trim();
  const buscable = !elegido && clave.length >= 2;

  useEffect(() => {
    if (!buscable) return;
    let vigente = true;
    const t = setTimeout(async () => {
      const r = await buscarRegistrosDe({ ente, texto: clave });
      if (!vigente) return;
      if (!r.success) toast.error(r.error);
      else setResultado({ clave, registros: r.registros });
    }, 250);
    return () => {
      vigente = false;
      clearTimeout(t);
    };
  }, [buscable, clave, ente]);

  if (elegido) {
    return (
      <div className="flex items-center gap-2 rounded-md border border-border px-3 py-2">
        <span className="t-body-m min-w-0 flex-1 truncate font-medium">{elegido.etiqueta}</span>
        <button type="button" className="btn btn-ghost btn-sm" aria-label="Cambiar" onClick={() => onElegir(null)}>
          <X size={14} />
        </button>
      </div>
    );
  }

  const registros = buscable && resultado?.clave === clave ? resultado.registros : null;
  return (
    <div className="flex flex-col gap-1">
      <SearchInput value={texto} onChange={setTexto} placeholder={placeholder} />
      {buscable && registros === null && <p className="t-caption text-text-tertiary">Buscando…</p>}
      {registros && registros.length === 0 && <p className="t-caption text-text-tertiary">Sin resultados.</p>}
      {registros && registros.length > 0 && (
        <ul className="flex flex-col">
          {registros.map((r) => (
            <li key={r.registro_id}>
              <button
                type="button"
                className="w-full rounded-md px-3 py-2 text-left hover:bg-bg-subtle"
                onClick={() => onElegir(r)}
              >
                <span className="t-body-m block font-medium text-text-primary">{r.etiqueta}</span>
                {r.detalle && <span className="t-caption block text-text-tertiary">{r.detalle}</span>}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
