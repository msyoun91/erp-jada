"use client";

import { useState } from "react";
import Link from "next/link";
import { Archive, ArchiveRestore, Copy, Globe, GlobeLock, Pencil, Play, Plus } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { SearchInput } from "@/components/ui/SearchInput";
import { copiarPlantilla, desactivarPlantilla, publicarPlantilla, reactivarPlantilla } from "../actions";
import { motivoRevisar } from "../derivados";
import { PRIORIDAD } from "../etiquetas";
import type { PlantillaCompleta } from "../queries";
import { TareasProvider, useNombre, useTareas, type TareasCtx } from "./contexto";
import { PlantillaFormPanel } from "./PlantillaFormPanel";
import { UsarPlantillaPanel } from "./UsarPlantillaPanel";

export type VerPlantillas = "mias" | "catalogo" | "otras";

type Dialogo =
  | { tipo: "nueva" }
  | { tipo: "editar" | "usar" | "desactivar"; plantilla: PlantillaCompleta };

type Resultado = { success: boolean; error?: string };

export function PlantillasView({
  plantillas,
  ver,
  ctx,
}: {
  plantillas: PlantillaCompleta[];
  ver: VerPlantillas;
  ctx: TareasCtx;
}) {
  return (
    <TareasProvider value={ctx}>
      <Contenido plantillas={plantillas} verInicial={ver} />
    </TareasProvider>
  );
}

function Contenido({ plantillas, verInicial }: { plantillas: PlantillaCompleta[]; verInicial: VerPlantillas }) {
  const { yo, admin, asignables, pedir } = useTareas();
  const nombre = useNombre();
  const [ver, setVer] = useState<VerPlantillas>(verInicial);
  const [texto, setTexto] = useState("");
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);

  const catalogo = plantillas.filter((p) => p.activo && p.publicada);
  const porVista: Record<VerPlantillas, PlantillaCompleta[]> = {
    mias: plantillas.filter((p) => p.dueno_id === yo),
    catalogo,
    // Lo que la RLS le deja ver al admin (*Función admin por módulo*).
    otras: plantillas.filter((p) => p.dueno_id !== yo),
  };
  const vistas: { valor: VerPlantillas; label: string }[] = [
    { valor: "mias", label: "Mis plantillas" },
    { valor: "catalogo", label: "Catálogo" },
    ...(admin ? [{ valor: "otras" as const, label: "De otros" }] : []),
  ];

  const q = texto.trim().toLowerCase();
  const filtradas = porVista[ver].filter((p) => p.nombre.toLowerCase().includes(q));
  const activas = filtradas.filter((p) => p.activo);
  const desactivadas = filtradas.filter((p) => !p.activo);

  async function correr(accion: Promise<Resultado>, ok: string) {
    const result = await accion;
    if (!result.success) toast.error(result.error);
    else toast.success(ok);
  }

  function tarjeta(p: PlantillaCompleta) {
    const mia = p.dueno_id === yo;
    const gestiona = mia || admin;
    const enCatalogo = ver === "catalogo";
    const revisar = p.tareas_plantillas_pasos.some((paso) => motivoRevisar(paso, asignables, pedir) !== null);
    const original = p.copiada_de ? catalogo.find((c) => c.id === p.copiada_de) : undefined;

    const menu = [
      ...(gestiona && p.activo && !enCatalogo
        ? [{ label: "Editar", icon: <Pencil size={14} />, onClick: () => setDialogo({ tipo: "editar", plantilla: p }) }]
        : []),
      ...(mia && p.activo && !p.publicada
        ? [{ label: "Publicar en el Catálogo", icon: <Globe size={14} />, onClick: () => correr(publicarPlantilla(p.id, true), "Publicada en el Catálogo") }]
        : []),
      ...(gestiona && p.activo && p.publicada
        ? [{ label: "Sacar del Catálogo", icon: <GlobeLock size={14} />, onClick: () => correr(publicarPlantilla(p.id, false), "Salió del Catálogo") }]
        : []),
      ...(gestiona && p.activo && !enCatalogo
        ? [{ label: "Desactivar", icon: <Archive size={14} />, onClick: () => setDialogo({ tipo: "desactivar", plantilla: p }), destructive: true }]
        : []),
      ...(admin && !p.activo
        ? [{ label: "Reactivar", icon: <ArchiveRestore size={14} />, onClick: () => correr(reactivarPlantilla(p.id), "Plantilla reactivada") }]
        : []),
    ];

    return (
      <div key={p.id} id={`plantilla-${p.id}`} className="card flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <p className="t-h3 min-w-0 flex-1">{p.nombre}</p>
          {!enCatalogo && p.publicada && <span className="badge badge-info">En el Catálogo</span>}
          {!enCatalogo && revisar && p.activo && <span className="badge badge-warning">A revisar</span>}
          {!p.activo && <span className="badge badge-neutral">Desactivada</span>}
          {enCatalogo && !mia && (
            <button className="btn btn-secondary btn-sm" onClick={() => correr(copiarPlantilla(p.id), "Copiada a Mis plantillas")}>
              <Copy size={14} />
              Copiar
            </button>
          )}
          {!enCatalogo && gestiona && p.activo && (
            <button className="btn btn-primary btn-sm" onClick={() => setDialogo({ tipo: "usar", plantilla: p })}>
              <Play size={14} />
              Usar
            </button>
          )}
          {menu.length > 0 && <OverflowMenu items={menu} />}
        </div>
        <p className="t-caption flex flex-wrap gap-x-3">
          <span>
            {p.tareas_plantillas_pasos.length} {p.tareas_plantillas_pasos.length === 1 ? "paso" : "pasos"}
          </span>
          {!mia && <span>De {nombre(p.dueno_id)}</span>}
          {p.copiada_de &&
            (original ? (
              <Link href={`/tareas/plantillas?ver=catalogo#plantilla-${original.id}`} className="text-text-brand hover:underline">
                Copia de «{original.nombre}»
              </Link>
            ) : (
              <span>Copia del Catálogo</span>
            ))}
        </p>
        {p.descripcion && <p className="t-body-m whitespace-pre-wrap">{p.descripcion}</p>}
        <details>
          <summary className="t-label cursor-pointer py-1">Ver pasos</summary>
          <ol className="mt-1 flex flex-col gap-1">
            {p.tareas_plantillas_pasos.map((paso, i) => {
              const motivo = enCatalogo ? null : motivoRevisar(paso, asignables, pedir);
              const fijo = paso.asignado_id ?? paso.asignado_equipo_id;
              return (
                <li key={paso.id} className={`t-body-m ${i > 0 && paso.espera_anterior ? "pl-6" : ""}`}>
                  <span className="font-medium">
                    {i + 1}. {paso.titulo}
                  </span>
                  <span className="t-caption ml-2 inline-flex flex-wrap gap-x-3">
                    <span>{fijo ? nombre(fijo) : "Se elige al usarla"}</span>
                    {i > 0 && paso.espera_anterior && <span>Espera al anterior</span>}
                    {paso.vence_dias && <span>Vence a los {paso.vence_dias} días</span>}
                    {paso.prioridad !== "media" && (
                      <span className={PRIORIDAD[paso.prioridad].clase}>Prioridad {PRIORIDAD[paso.prioridad].label.toLowerCase()}</span>
                    )}
                    {motivo && (
                      <span className="text-warning-text">
                        {motivo === "pedido" ? "ya no es de tu equipo y no podés pedir afuera" : "ya no puede recibir"}
                      </span>
                    )}
                  </span>
                </li>
              );
            })}
          </ol>
        </details>
      </div>
    );
  }

  const vacio =
    porVista[ver].length > 0
      ? "Sin resultados. Probá con otro término."
      : ver === "mias"
        ? 'Armá una con "Nueva plantilla" o copiá una del Catálogo.'
        : ver === "catalogo"
          ? "Nadie publicó una plantilla todavía."
          : "Nadie más tiene plantillas.";

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="flex rounded-lg border border-border p-0.5" role="group" aria-label="Qué ver">
          {vistas.map((v) => (
            <button
              key={v.valor}
              onClick={() => setVer(v.valor)}
              aria-pressed={v.valor === ver}
              className={`tap-target t-caption flex items-center rounded-md px-3 py-1 ${
                v.valor === ver ? "bg-brand-50 font-semibold text-brand-700" : "text-text-tertiary"
              }`}
            >
              {v.label}
            </button>
          ))}
        </div>
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar plantilla…" />
        {ver === "mias" && (
          <button className="btn btn-primary" onClick={() => setDialogo({ tipo: "nueva" })}>
            <Plus size={16} />
            Nueva plantilla
          </button>
        )}
      </div>

      {activas.length === 0 ? (
        <div className="empty-state">
          <p className="t-body-m">{vacio}</p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">{activas.map(tarjeta)}</div>
      )}
      {desactivadas.length > 0 && (
        <details className="mt-3">
          <summary className="t-label cursor-pointer py-2">Desactivadas ({desactivadas.length})</summary>
          <div className="flex flex-col gap-3">{desactivadas.map(tarjeta)}</div>
        </details>
      )}

      {dialogo?.tipo === "nueva" && <PlantillaFormPanel onClose={() => setDialogo(null)} />}
      {dialogo?.tipo === "editar" && <PlantillaFormPanel plantilla={dialogo.plantilla} onClose={() => setDialogo(null)} />}
      {dialogo?.tipo === "usar" && <UsarPlantillaPanel plantillas={[dialogo.plantilla]} onClose={() => setDialogo(null)} />}
      {dialogo?.tipo === "desactivar" && (
        <ConfirmModal
          title="Desactivar plantilla"
          mensaje={`¿Desactivar "${dialogo.plantilla.nombre}"?${dialogo.plantilla.publicada ? " Sale del Catálogo." : ""} Los hilos que ya creó no cambian.`}
          onConfirm={() => correr(desactivarPlantilla(dialogo.plantilla.id), "Plantilla desactivada")}
          onClose={() => setDialogo(null)}
        />
      )}
    </div>
  );
}
