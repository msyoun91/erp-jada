import { notFound } from "next/navigation";
import { puedeAprobar, puedeArmar, puedeVerPaquetes } from "@/modules/catalogo/permissions";
import { getCategorias, getPaquetes } from "@/modules/catalogo/queries";
import { PaquetesView } from "@/modules/catalogo/components/PaquetesView";

export default async function PaquetesPage() {
  if (!(await puedeVerPaquetes())) notFound();

  const [paquetes, categorias, armar, aprobar] = await Promise.all([
    getPaquetes(),
    getCategorias("paquete"),
    puedeArmar(),
    puedeAprobar(),
  ]);

  return <PaquetesView paquetes={paquetes} categorias={categorias} puedeArmar={armar} puedeAprobar={aprobar} />;
}
