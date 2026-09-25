import Link from "next/link";
import type { Mencion } from "../queries";

export function Menciones({ menciones }: { menciones: Mencion[] }) {
  if (menciones.length === 0) return null;
  return (
    <div>
      <p className="t-label mb-2">Mencionado en</p>
      <ul className="flex flex-col gap-1">
        {menciones.map((m) => (
          <li key={m.pasoId} className="t-body-m">
            <Link href={`/tareas/paso/${m.pasoId}`} className="text-text-brand hover:underline">
              {m.titulo}
            </Link>
            <span className="t-caption"> · {m.hilo}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
