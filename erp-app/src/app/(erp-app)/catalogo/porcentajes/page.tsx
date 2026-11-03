import { notFound } from "next/navigation";
import { puedeEditarPorcentajes, puedeVerPorcentajes } from "@/modules/catalogo/permissions";
import { getCategorias, getMonedaPrincipal, getPorcentajes } from "@/modules/catalogo/queries";
import { PorcentajesView } from "@/modules/catalogo/components/PorcentajesView";

export default async function PorcentajesPage() {
  if (!(await puedeVerPorcentajes())) notFound();

  const [porcentajes, categoriasInsumo, categoriasServicio, editar, monedaPrincipal] = await Promise.all([
    getPorcentajes(),
    getCategorias("insumo"),
    getCategorias("servicio"),
    puedeEditarPorcentajes(),
    getMonedaPrincipal(),
  ]);

  return (
    <PorcentajesView
      porcentajes={porcentajes}
      categoriasInsumo={categoriasInsumo}
      categoriasServicio={categoriasServicio}
      puedeEditar={editar}
      monedaPrincipal={monedaPrincipal}
    />
  );
}
