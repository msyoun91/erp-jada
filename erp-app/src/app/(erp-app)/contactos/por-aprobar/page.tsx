import { notFound } from "next/navigation";
import { puedeAprobar } from "@/modules/contactos/permissions";
import { getPorAprobar } from "@/modules/contactos/queries";
import { PorAprobarView } from "@/modules/contactos/components/PorAprobarView";

// La función "Aprobar altas" (`contactos_aprobar`), dentro de la vista Contactos.
export default async function PorAprobarPage() {
  if (!(await puedeAprobar())) notFound();
  return <PorAprobarView contactos={await getPorAprobar()} />;
}
