import Link from "next/link";
import { ExternalLink } from "lucide-react";
import { origenHref } from "../origen";

// "Generado por X": link solo si el punto es una ruta interna (`origen.ts`).
export function OrigenLink({ app, punto }: { app: string; punto: string | null }) {
  const href = origenHref(punto);
  const contenido = (
    <>
      <ExternalLink size={13} strokeWidth={1.75} />
      Generado por {app}
      {href && " — ir"}
    </>
  );
  return href ? (
    <Link href={href} className="flex items-center gap-1 text-brand-500 hover:underline">
      {contenido}
    </Link>
  ) : (
    <span className="flex items-center gap-1">{contenido}</span>
  );
}
