"use client";

import { useState } from "react";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { desactivarEmpresa } from "../actions";
import {
  LABEL_ESTADO,
  LABEL_PROVINCIA,
  LABEL_ROL_EMPRESA,
  type Empresa,
  type EstadoObra,
  type RolEmpresa,
} from "../types";
import { EmpresaFormPanel } from "./EmpresaFormPanel";

export function EmpresaDetalle({
  empresa,
  personas,
  obras,
  puedeEditar,
}: {
  empresa: Empresa;
  personas: { id: string; persona_id: string; nombre: string; cargo: string | null; es_principal: boolean }[];
  obras: { id: string; obra_id: string; nombre: string; estado: EstadoObra; localidad: string | null; roles: RolEmpresa[] }[];
  puedeEditar: boolean;
}) {
  const [editando, setEditando] = useState(false);
  const [desactivando, setDesactivando] = useState(false);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2">
        <Link href="/obras/empresas" className="btn btn-ghost btn-sm">
          ← Empresas
        </Link>
        <h2 className="t-h2 min-w-0 flex-1 truncate">{empresa.razon_social}</h2>
        {puedeEditar && (
          <>
            <button className="btn btn-secondary btn-sm" onClick={() => setEditando(true)}>
              <Pencil size={14} />
              Editar
            </button>
            <button className="btn btn-danger btn-sm" onClick={() => setDesactivando(true)}>
              Desactivar
            </button>
          </>
        )}
      </div>

      <section className="card p-4">
        <dl className="grid grid-cols-2 gap-4 md:grid-cols-3">
          {empresa.nombre_comercial && (
            <div>
              <dt className="t-caption">Nombre comercial</dt>
              <dd className="t-body-m">{empresa.nombre_comercial}</dd>
            </div>
          )}
          {empresa.telefono && (
            <div>
              <dt className="t-caption">Teléfono</dt>
              <dd className="t-body-m">{empresa.telefono}</dd>
            </div>
          )}
          {empresa.email && (
            <div>
              <dt className="t-caption">Email</dt>
              <dd className="t-body-m">{empresa.email}</dd>
            </div>
          )}
          {empresa.website && (
            <div>
              <dt className="t-caption">Website</dt>
              <dd className="t-body-m">{empresa.website}</dd>
            </div>
          )}
          {empresa.direccion && (
            <div>
              <dt className="t-caption">Dirección</dt>
              <dd className="t-body-m">{empresa.direccion}</dd>
            </div>
          )}
          {empresa.localidad && (
            <div>
              <dt className="t-caption">Localidad</dt>
              <dd className="t-body-m">
                {empresa.localidad}
                {empresa.provincia && `, ${LABEL_PROVINCIA[empresa.provincia]}`}
              </dd>
            </div>
          )}
        </dl>
        {empresa.observaciones && (
          <p className="t-body-m mt-4 whitespace-pre-wrap">{empresa.observaciones}</p>
        )}
      </section>

      <section>
        <h3 className="t-h3 mb-2">Personas</h3>
        {personas.length === 0 ? (
          <p className="t-caption">Ninguna persona vinculada a tu alcance.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {personas.map((p) => (
              <li key={p.id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <Link
                  href={`/obras/personas/${p.persona_id}`}
                  className="t-body-m min-w-0 flex-1 truncate font-semibold hover:underline"
                >
                  {p.nombre}
                </Link>
                {p.cargo && <span className="t-caption">{p.cargo}</span>}
                {p.es_principal && <span className="badge badge-neutral">Principal</span>}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <h3 className="t-h3 mb-2">Obras</h3>
        {obras.length === 0 ? (
          // Las obras ajenas no se ven: la empresa es compartida, las obras no.
          <p className="t-caption">Ninguna de tus obras tiene vinculada esta empresa.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {obras.map((o) => (
              <li key={o.id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <Link
                  href={`/obras/${o.obra_id}`}
                  className="t-body-m min-w-0 flex-1 truncate font-semibold hover:underline"
                >
                  {o.nombre}
                </Link>
                <span className="t-caption">{LABEL_ESTADO[o.estado]}</span>
                {o.localidad && <span className="t-caption">{o.localidad}</span>}
                <span className="t-caption">
                  {o.roles.map((r) => LABEL_ROL_EMPRESA[r]).join(" · ")}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {editando && <EmpresaFormPanel empresa={empresa} onClose={() => setEditando(false)} />}

      {desactivando && (
        <ConfirmModal
          title="Desactivar empresa"
          mensaje="Si participa en alguna obra activa —incluidas obras que no ves— la base lo va a impedir. Desvinculala primero."
          onConfirm={async () => {
            const result = await desactivarEmpresa(empresa.id);
            if (result.success) toast.success("Empresa desactivada");
            else toast.error(result.error);
          }}
          onClose={() => setDesactivando(false)}
        />
      )}
    </div>
  );
}
