import { notFound } from "next/navigation";
import {
  puedeGestionarObras,
  puedeVerComision,
  puedeVerObras,
} from "@/modules/comercial/permissions";
import { getEmpresas, getObras, getPersonas } from "@/modules/comercial/queries";
import { ObrasView } from "@/modules/comercial/components/ObrasView";

export default async function ObrasPage() {
  if (!(await puedeVerObras())) notFound();

  const [obras, empresas, personas, gestionar, verComision] = await Promise.all([
    getObras(),
    getEmpresas(),
    getPersonas(),
    puedeGestionarObras(),
    puedeVerComision(),
  ]);

  return (
    <ObrasView
      obras={obras}
      empresas={empresas}
      personas={personas}
      puedeGestionar={gestionar}
      verComision={verComision}
    />
  );
}
