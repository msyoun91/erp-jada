"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Modal } from "@/components/ui/Modal";
import { SearchInput } from "@/components/ui/SearchInput";
import { LABEL_MAP } from "@/components/layout/SidebarNav";
import { buscarRegistros, modulosRelacionables } from "../actions";
import type { RegistroEncontrado } from "../types";

const ETIQUETA_ENTE: Record<string, string> = { hilo: "Hilo", tarea: "Paso" };

// Primero el módulo, después el buscador: solo lo que quien escribe ve
// (`buscar_registros`). Elegir un registro lo devuelve y cierra.
export function RelacionarModal({
  onElegir,
  onClose,
}: {
  onElegir: (r: RegistroEncontrado) => void;
  onClose: () => void;
}) {
  const [modulos, setModulos] = useState<string[] | null>(null);
  const [modulo, setModulo] = useState("");
  const [texto, setTexto] = useState("");
  const [resultado, setResultado] = useState<{ clave: string; registros: RegistroEncontrado[] } | null>(null);
  const clave = `${modulo}:${texto.trim()}`;
  const buscable = modulo !== "" && texto.trim().length >= 2;

  useEffect(() => {
    modulosRelacionables().then((r) => {
      if (!r.success) {
        toast.error(r.error);
        return;
      }
      setModulos(r.modulos);
      if (r.modulos.length === 1) setModulo(r.modulos[0]);
    });
  }, []);

  useEffect(() => {
    if (!buscable) return;
    let vigente = true;
    const t = setTimeout(async () => {
      const r = await buscarRegistros({ modulo, texto });
      if (!vigente) return;
      if (!r.success) toast.error(r.error);
      else setResultado({ clave, registros: r.registros });
    }, 250);
    return () => {
      vigente = false;
      clearTimeout(t);
    };
  }, [buscable, clave, modulo, texto]);

  const registros = buscable && resultado?.clave === clave ? resultado.registros : null;

  return (
    <Modal title="Relacionar" onClose={onClose} maxWidth={520}>
      <div className="flex flex-col gap-3">
        {modulos && modulos.length > 1 && (
          <select
            aria-label="Módulo"
            className="input"
            value={modulo}
            onChange={(e) => setModulo(e.target.value)}
          >
            <option value="">Elegí el módulo</option>
            {modulos.map((m) => (
              <option key={m} value={m}>
                {LABEL_MAP[m] ?? m}
              </option>
            ))}
          </select>
        )}
        {modulos && modulos.length === 0 && (
          <p className="t-body-m text-text-secondary">No hay nada que puedas relacionar.</p>
        )}
        {modulo && <SearchInput value={texto} onChange={setTexto} placeholder="Buscar por nombre" autoFocus />}

        {modulo && !buscable && <p className="t-caption text-text-tertiary">Escribí al menos dos letras.</p>}
        {buscable && registros === null && <p className="t-caption text-text-tertiary">Buscando…</p>}
        {registros && registros.length === 0 && <p className="t-caption text-text-tertiary">Sin resultados.</p>}
        {registros && registros.length > 0 && (
          <ul className="flex flex-col">
            {registros.map((r) => (
              <li key={`${r.ente}:${r.registro_id}`}>
                <button
                  type="button"
                  className="w-full rounded-md px-3 py-2 text-left hover:bg-bg-subtle"
                  onClick={() => onElegir(r)}
                >
                  <span className="t-body-m block font-medium text-text-primary">{r.etiqueta}</span>
                  <span className="t-caption block text-text-tertiary">
                    {ETIQUETA_ENTE[r.ente] ?? r.ente}
                    {r.detalle ? ` · ${r.detalle}` : ""}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </Modal>
  );
}
