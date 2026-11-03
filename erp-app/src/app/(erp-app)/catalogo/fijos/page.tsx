import { notFound } from "next/navigation";
import { puedeEditarFijos, puedeVerFijos } from "@/modules/catalogo/permissions";
import { getCategorias, getInsumos, getMonedaPrincipal } from "@/modules/catalogo/queries";
import { InsumosView } from "@/modules/catalogo/components/InsumosView";

// Una sola función para todo: alta con costo, edición, costo, baja y categorías.
export default async function FijosPage() {
  if (!(await puedeVerFijos())) notFound();

  const [fijos, categorias, editar, monedaPrincipal] = await Promise.all([
    getInsumos("servicio"),
    getCategorias("servicio"),
    puedeEditarFijos(),
    getMonedaPrincipal(),
  ]);

  return (
    <InsumosView
      tipo="servicio"
      insumos={fijos}
      categorias={categorias}
      colores={[]}
      puedeEditar={editar}
      puedeCostos={editar}
      monedaPrincipal={monedaPrincipal}
    />
  );
}
