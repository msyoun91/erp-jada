import { notFound } from "next/navigation";
import { puedeGestionarPersonas, puedeVerPersonas } from "@/modules/comercial/permissions";
import { getEmpresas, getPersonas } from "@/modules/comercial/queries";
import { PersonasView } from "@/modules/comercial/components/PersonasView";

export default async function PersonasPage() {
  if (!(await puedeVerPersonas())) notFound();

  const [personas, empresas, gestionar] = await Promise.all([
    getPersonas(),
    getEmpresas(),
    puedeGestionarPersonas(),
  ]);

  return <PersonasView personas={personas} empresas={empresas} puedeGestionar={gestionar} />;
}
