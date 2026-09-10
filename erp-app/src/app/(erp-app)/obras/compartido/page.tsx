import { notFound } from "next/navigation";
import { puedeVerCompartido } from "@/modules/obras/permissions";
import { getCompartidosPorMi } from "@/modules/obras/queries";
import { CompartidoView } from "@/modules/obras/components/CompartidoView";

export default async function ObrasCompartidoPage() {
  if (!(await puedeVerCompartido())) notFound();

  const filas = await getCompartidosPorMi();

  return <CompartidoView filas={filas} />;
}
