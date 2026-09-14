import Link from "next/link";
import { X } from "lucide-react";
import { ENTES } from "@/lib/entes";

// Los registros con los que se relaciona una tarea: con `href`, el chip abre
// la ficha; con `quitable` y `onQuitar`, lleva ×.
export function VinculosChips({
  vinculos,
  onQuitar,
}: {
  vinculos: { key: string; ente: string; etiqueta: string; href?: string; quitable?: boolean }[];
  onQuitar?: (key: string) => void;
}) {
  if (vinculos.length === 0) return null;

  return (
    <ul className="flex min-w-0 flex-wrap gap-1.5">
      {vinculos.map((v) => {
        const conX = Boolean(onQuitar && v.quitable);
        const texto = (
          <>
            <span className="font-normal opacity-75">{ENTES[v.ente]?.nombre ?? v.ente}</span> {v.etiqueta}
          </>
        );
        return (
          <li
            key={v.key}
            className={`t-caption inline-flex max-w-full items-center gap-1 rounded-full bg-brand-50 py-0.5 pl-2.5 font-medium text-brand-700 ${conX ? "pr-1" : "pr-2.5"}`}
          >
            {v.href ? (
              <Link href={v.href} className="truncate hover:underline">
                {texto}
              </Link>
            ) : (
              <span className="truncate">{texto}</span>
            )}
            {conX && (
              <button
                type="button"
                className="tap-target rounded-full p-0.5 hover:bg-brand-100"
                aria-label={`Quitar ${v.etiqueta}`}
                onClick={() => onQuitar?.(v.key)}
              >
                <X size={12} />
              </button>
            )}
          </li>
        );
      })}
    </ul>
  );
}
