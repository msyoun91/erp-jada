import { notFound } from "next/navigation";
import { puedeConfigurar } from "@/modules/presupuestos/permissions";
import { getConfiguraciones } from "@/modules/presupuestos/queries";
import { ConfiguracionView } from "@/modules/presupuestos/components/ConfiguracionView";

export default async function ConfiguracionPage() {
  if (!(await puedeConfigurar())) notFound();
  return <ConfiguracionView configuraciones={await getConfiguraciones()} />;
}
