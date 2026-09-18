"use client";

import { useState } from "react";
import Link from "next/link";
import { Building2, HardHat, Share2, UserRound, X } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { formatFecha } from "@/lib/utils";
import { revocarContextual, revocarObra } from "../actions";
import type { CompartidoRow } from "../types";

const ICONO = {
  obra: HardHat,
  empresa: Building2,
  persona: UserRound,
} as const;

const HREF = {
  obra: (id: string) => `/obras/${id}`,
  empresa: (id: string) => `/obras/empresas/${id}`,
  persona: (id: string) => `/obras/personas/${id}`,
} as const;

// Toda fila que no es una obra cuelga de un ancla: revocarla es destildarla del
// checklist, desde el otro lado (sql/086). El ancla puede ser una obra o —para
// una persona que llegó por el estado 2 de una transferencia— una empresa, y
// hay que pasar cuál: la firma vieja asumía obra y esas filas no se podían
// revocar nunca (sql/090).
function revocar(fila: CompartidoRow) {
  if (fila.tipo === "obra") return revocarObra(fila.entidad_id, fila.usuario_id);
  if (!fila.origen_tipo || !fila.origen_id) {
    return Promise.resolve({ success: false as const, error: "Sin origen" });
  }
  return revocarContextual(
    fila.tipo,
    fila.entidad_id,
    fila.usuario_id,
    fila.origen_tipo,
    fila.origen_id,
  );
}

// Anidada, el ancla está arriba y alcanza con el tipo. Suelta —el ancla no vino
// en el resultado— hace falta el nombre, y la base no lo manda si no la puedo
// abrir (sql/099).
function via(f: CompartidoRow, anidada: boolean) {
  const cual = f.origen_tipo === "obra" ? "la obra" : "la empresa";
  if (anidada) return `vía ${cual}`;
  if (f.origen_nombre) return `vía ${cual} ${f.origen_nombre}`;
  return f.origen_tipo === "obra"
    ? "vía una obra que no podés abrir"
    : "vía una empresa que no podés abrir";
}

const filaKey = (f: CompartidoRow) => `${f.tipo}:${f.entidad_id}:${f.usuario_id}`;
const padreKey = (f: CompartidoRow) =>
  f.origen_tipo && f.origen_id ? `${f.origen_tipo}:${f.origen_id}:${f.usuario_id}` : null;

export function CompartidoView({ filas }: { filas: CompartidoRow[] }) {
  const [confirmando, setConfirmando] = useState<CompartidoRow | null>(null);

  // El árbol se arma antes del estado vacío: `usePaginado` es un hook y no
  // puede quedar detrás de un `return`.
  //
  // Lo compartido en cascada se anida bajo la obra/empresa de la que cuelga.
  // El padre siempre está en el mismo resultado (obras_compartir_* inserta su
  // grant antes que la cascada); si no estuviera, la fila queda como raíz.
  const presentes = new Set(filas.map(filaKey));
  const hijosDe = new Map<string, CompartidoRow[]>();
  for (const f of filas) {
    const pk = padreKey(f);
    if (pk && presentes.has(pk)) {
      const lista = hijosDe.get(pk);
      if (lista) lista.push(f);
      else hijosDe.set(pk, [f]);
    }
  }
  const raices = filas.filter((f) => {
    const pk = padreKey(f);
    return !pk || !presentes.has(pk);
  });
  // Pagina las raíces: cada una se lleva sus anidadas, que no son filas
  // sueltas sino el reparto de esa obra.
  const { visibles, ...paginado } = usePaginado(raices);

  async function correr(fila: CompartidoRow) {
    const result = await revocar(fila);
    if (result.success) toast.success("Acceso revocado");
    else toast.error(result.error);
  }

  if (filas.length === 0) {
    return (
      <div className="empty-state">
        <Share2 size={30} strokeWidth={1.5} className="mx-auto mb-3" />
        <p className="t-h3">No compartiste nada</p>
        <p className="t-body-m mt-1">
          Compartí una obra desde su ficha y va a aparecer acá.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <p className="t-body-m mb-2 max-w-prose">
        Todo lo que compartiste y con quién. Las empresas y personas que tildaste aparecen
        anidadas bajo su obra: se abren solo desde ahí, no entran a la agenda del otro. Quien
        recibe no puede editar ni re-compartir. Revocar la obra saca todo lo que la acompaña.
      </p>

      <Paginacion {...paginado} etiqueta="obras compartidas" />

      <ul className="flex flex-col gap-2">
        {visibles.map((f) => (
          <Fila
            key={filaKey(f)}
            f={f}
            anidada={false}
            hijosDe={hijosDe}
            onRevocar={setConfirmando}
          />
        ))}
      </ul>

      {confirmando && (
        <ConfirmModal
          title="Revocar acceso"
          mensaje={`${confirmando.usuario_nombre} deja de ver «${confirmando.entidad_nombre}».${
            confirmando.tipo === "obra"
              ? " Lo que se compartió junto con esta obra también se revoca, y los vínculos que haya armado con contactos suyos se desactivan."
              : " Deja de abrirse desde esa obra."
          }`}
          confirmLabel="Revocar"
          onConfirm={() => correr(confirmando)}
          onClose={() => setConfirmando(null)}
        />
      )}
    </div>
  );
}

// A nivel de módulo y no adentro de `CompartidoView`: declarada en el cuerpo,
// React la trata como un tipo nuevo en cada render y remontaba el árbol entero
// al abrir la confirmación.
function Fila({
  f,
  anidada,
  hijosDe,
  onRevocar,
}: {
  f: CompartidoRow;
  anidada: boolean;
  hijosDe: Map<string, CompartidoRow[]>;
  onRevocar: (fila: CompartidoRow) => void;
}) {
  const Icono = ICONO[f.tipo];
  const hijos = hijosDe.get(filaKey(f)) ?? [];
  return (
    <li>
      <div className="card flex items-center gap-3 p-3">
        <Icono size={18} strokeWidth={1.75} className="text-brand-500 shrink-0" />
        <div className="min-w-0 flex-1">
          {/* El dueño del ancla ve filas de contactos que no son suyos
              (sql/093): el nombre sí, la ficha no. Sin link es el mismo techo
              que ya tiene la ficha de la obra, que muestra el nombre del
              contacto ajeno y no el teléfono. */}
          {f.puedo_abrir ? (
            <Link
              href={HREF[f.tipo](f.entidad_id)}
              className="t-body-m block truncate font-semibold hover:underline"
            >
              {f.entidad_nombre}
            </Link>
          ) : (
            <p className="t-body-m truncate font-semibold">{f.entidad_nombre}</p>
          )}
          <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
            <span className="t-caption">con {f.usuario_nombre}</span>
            <span className="t-caption">· {formatFecha(f.compartida_el)}</span>
            {f.origen_tipo && (
              <span className="badge badge-neutral max-w-full truncate">{via(f, anidada)}</span>
            )}
          </div>
        </div>
        <button
          type="button"
          className="icon-btn text-text-tertiary"
          aria-label={`Revocar acceso de ${f.usuario_nombre} a ${f.entidad_nombre}`}
          onClick={() => onRevocar(f)}
        >
          <X size={16} strokeWidth={1.75} />
        </button>
      </div>
      {hijos.length > 0 && (
        <ul className="border-border mt-2 ml-4 flex flex-col gap-2 border-l pl-4">
          {hijos.map((h) => (
            <Fila key={filaKey(h)} f={h} anidada hijosDe={hijosDe} onRevocar={onRevocar} />
          ))}
        </ul>
      )}
    </li>
  );
}
