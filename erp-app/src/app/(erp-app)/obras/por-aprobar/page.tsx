import { notFound } from "next/navigation";
import { puedeAprobar } from "@/modules/obras/permissions";
import { getPorAprobar } from "@/modules/obras/queries";
import { PorAprobarView } from "@/modules/obras/components/PorAprobarView";

// La función "Aprobar altas" (`obras_aprobar`), dentro de la vista Obras.
export default async function PorAprobarPage() {
  if (!(await puedeAprobar())) notFound();
  return <PorAprobarView obras={await getPorAprobar()} />;
}
