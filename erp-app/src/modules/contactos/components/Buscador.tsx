"use client";

import { useState } from "react";
import { Building2, Plus, UserRound } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import { buscarEmpresas, buscarVinculables } from "../actions";
import type { Vinculable } from "../types";
import { useBusqueda } from "./useBusqueda";

export type TipoContacto = "persona" | "empresa";

export function IconoContacto({ tipo }: { tipo: TipoContacto }) {
  const Icono = tipo === "persona" ? UserRound : Building2;
  return <Icono size={14} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />;
}

function Opcion({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        className="tap-target flex w-full items-center gap-2 rounded-md px-3 py-2 text-left hover:bg-bg-subtle"
      >
        {children}
      </button>
    </li>
  );
}

// Lo que quien busca puede vincular (`contactos_vinculables`): sus personas y
// las empresas de su equipo. Si no está, al pie, crearlo con el texto escrito.
export function BuscadorVinculables({
  tipos = ["persona", "empresa"],
  onElegir,
  onCrear,
}: {
  tipos?: TipoContacto[];
  onElegir: (v: Vinculable) => void;
  onCrear?: (tipo: TipoContacto, nombre: string) => void;
}) {
  const [texto, setTexto] = useState("");
  const { buscable, resultados } = useBusqueda(texto, buscarVinculables);
  const visibles = resultados?.filter((r) => tipos.includes(r.tipo as TipoContacto));

  return (
    <div className="flex flex-col gap-2">
      <SearchInput
        value={texto}
        onChange={setTexto}
        placeholder={tipos.length === 1 ? "Buscar persona" : "Buscar persona o empresa"}
        autoFocus
      />
      {!buscable && <p className="t-caption text-text-tertiary">Escribí al menos dos letras.</p>}
      {buscable && visibles === undefined && <p className="t-caption text-text-tertiary">Buscando…</p>}
      {visibles && (
        <ul className="flex flex-col">
          {visibles.length === 0 && <li className="t-caption px-3 py-2 text-text-tertiary">Sin resultados.</li>}
          {visibles.map((r) => (
            <Opcion key={r.id} onClick={() => onElegir(r)}>
              <IconoContacto tipo={r.tipo as TipoContacto} />
              <span className="min-w-0 flex-1">
                <span className="t-body-m block truncate font-medium text-text-primary">{r.nombre}</span>
                {r.detalle && <span className="t-caption block truncate">{r.detalle}</span>}
              </span>
            </Opcion>
          ))}
          {onCrear &&
            tipos.map((tipo) => (
              <Opcion key={`crear-${tipo}`} onClick={() => onCrear(tipo, texto.trim())}>
                <Plus size={14} strokeWidth={1.75} className="shrink-0 text-text-brand" />
                <span className="t-body-m text-text-brand">
                  Crear «{texto.trim()}» como {tipo}
                </span>
              </Opcion>
            ))}
        </ul>
      )}
    </div>
  );
}

export type EmpresaElegida = { id: string | null; nombre: string };

// La empresa de una persona: una que se ve (las del registro, primero) o una
// nueva con solo el nombre (`id` null). Un solo nivel: desde acá no se crea más.
export function EmpresaSelector({
  valor,
  onCambio,
  sugeridas = [],
  crear,
}: {
  valor: EmpresaElegida | null;
  onCambio: (e: EmpresaElegida | null) => void;
  sugeridas?: { id: string; nombre: string }[];
  crear?: boolean;
}) {
  const [texto, setTexto] = useState("");
  const { buscable, resultados } = useBusqueda(texto, buscarEmpresas);

  if (valor) {
    return (
      <div className="flex items-center gap-2 rounded-md border border-border px-3 py-2">
        <IconoContacto tipo="empresa" />
        <span className="t-body-m min-w-0 flex-1 truncate">{valor.nombre}</span>
        {valor.id === null && <span className="badge badge-info">Nueva</span>}
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onCambio(null)}>
          Cambiar
        </button>
      </div>
    );
  }

  const lista = buscable ? resultados : sugeridas;
  return (
    <div className="flex flex-col gap-1">
      <SearchInput value={texto} onChange={setTexto} placeholder="Buscar empresa" />
      {buscable && lista === null && <p className="t-caption text-text-tertiary">Buscando…</p>}
      {lista && (lista.length > 0 || (buscable && crear)) && (
        <ul className="flex flex-col">
          {lista.map((e) => (
            <Opcion key={e.id} onClick={() => onCambio(e)}>
              <IconoContacto tipo="empresa" />
              <span className="t-body-m truncate">{e.nombre}</span>
            </Opcion>
          ))}
          {buscable && crear && (
            <Opcion onClick={() => onCambio({ id: null, nombre: texto.trim() })}>
              <Plus size={14} strokeWidth={1.75} className="shrink-0 text-text-brand" />
              <span className="t-body-m text-text-brand">Crear «{texto.trim()}»</span>
            </Opcion>
          )}
        </ul>
      )}
    </div>
  );
}
