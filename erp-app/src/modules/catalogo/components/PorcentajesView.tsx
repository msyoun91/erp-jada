"use client";

import { useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import type { Moneda } from "@/lib/monedas";
import { PASO, textoBase, textoMinimo, textoPorcentaje } from "../etiquetas";
import type { Categoria, Porcentaje } from "../types";
import { PorcentajeFormPanel } from "./PorcentajeFormPanel";

// Agrupados por paso, que es el orden del cálculo: dentro de un paso ninguno se calcula sobre otro.
export function PorcentajesView({
  porcentajes,
  categoriasInsumo,
  categoriasServicio,
  puedeEditar,
  monedaPrincipal,
}: {
  porcentajes: Porcentaje[];
  categoriasInsumo: Categoria[];
  categoriasServicio: Categoria[];
  puedeEditar: boolean;
  monedaPrincipal: Moneda;
}) {
  const [creando, setCreando] = useState(false);
  const [verBajas, setVerBajas] = useState(false);
  const nombreCategoria = new Map([...categoriasInsumo, ...categoriasServicio].map((c) => [c.id, c.nombre]));
  const visibles = porcentajes.filter((p) => verBajas || !p.de_baja);
  const sumaPaso3 = porcentajes.filter((p) => p.paso === 3 && !p.de_baja).reduce((s, p) => s + p.porcentaje, 0);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-3">
        {puedeEditar && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nuevo servicio en %
          </button>
        )}
        <label className="tap-target flex items-center gap-2">
          <input type="checkbox" checked={verBajas} onChange={(e) => setVerBajas(e.target.checked)} />
          <span className="t-body-m">Ver los de baja</span>
        </label>
      </div>

      {porcentajes.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin servicios en % todavía</p>
          <p className="t-body-m mt-1">
            {puedeEditar
              ? 'Cargá el primero con "Nuevo servicio en %": comercialización, garantías, IIBB.'
              : "Todavía nadie cargó servicios en %."}
          </p>
        </div>
      ) : (
        [1, 2, 3].map((paso) => {
          const lista = visibles.filter((p) => p.paso === paso);
          return (
            <section key={paso} className="flex flex-col gap-2">
              <div className="flex items-baseline justify-between gap-2">
                <h2 className="t-label">{PASO[paso].titulo}</h2>
                {paso === 3 && <span className="t-caption">Suman {textoPorcentaje(sumaPaso3)}</span>}
              </div>
              {lista.length === 0 ? (
                <p className="t-caption">Ninguno.</p>
              ) : (
                <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
                  {lista.map((p) => {
                    const detalle = [textoBase(p, nombreCategoria), textoMinimo(p)].filter(Boolean).join(" · ");
                    return (
                      <li key={p.id} className="border-b border-border last:border-b-0">
                        <Link
                          href={`/catalogo/porcentajes/${p.id}`}
                          className="row tap-target flex items-center gap-3 hover:bg-bg-subtle"
                        >
                          <div className="min-w-0 flex-1">
                            <p
                              className={`t-body-m truncate font-medium ${p.de_baja ? "text-text-tertiary" : "text-text-primary"}`}
                            >
                              {p.nombre}
                            </p>
                            {detalle && <p className="t-caption truncate">{detalle}</p>}
                          </div>
                          {p.opcional && <span className="badge badge-neutral shrink-0">Opcional</span>}
                          {p.de_baja && <span className="badge badge-neutral shrink-0">De baja</span>}
                          <span className="t-body-m shrink-0 font-semibold">{textoPorcentaje(p.porcentaje)}</span>
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              )}
            </section>
          );
        })
      )}

      {creando && (
        <PorcentajeFormPanel
          porcentaje={null}
          categoriasInsumo={categoriasInsumo}
          categoriasServicio={categoriasServicio}
          monedaPrincipal={monedaPrincipal}
          onClose={() => setCreando(false)}
        />
      )}
    </div>
  );
}
