import Link from "next/link";
import { ArrowLeft } from "lucide-react";

// La vuelta de toda ficha a su listado. El breadcrumb orienta pero no navega,
// y un módulo con una sola tab no muestra tabs: sin esto, de una obra o un hilo
// se salía con el atrás del browser o abriendo el menú.
export function Volver({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link href={href} className="tap-target t-body-m flex w-fit items-center gap-1 text-text-brand hover:text-brand-500">
      <ArrowLeft size={14} />
      {children}
    </Link>
  );
}
