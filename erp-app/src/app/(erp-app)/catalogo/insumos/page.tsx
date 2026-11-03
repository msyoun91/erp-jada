import { notFound } from "next/navigation";
import { puedeCargar, puedeCostos, puedeVerInsumos } from "@/modules/catalogo/permissions";
import { getCategorias, getColores, getInsumos, getMonedaPrincipal } from "@/modules/catalogo/queries";
import { InsumosView } from "@/modules/catalogo/components/InsumosView";

export default async function InsumosPage() {
  if (!(await puedeVerInsumos())) notFound();

  const [insumos, categorias, colores, cargar, costos, monedaPrincipal] = await Promise.all([
    getInsumos("insumo"),
    getCategorias("insumo"),
    getColores(),
    puedeCargar(),
    puedeCostos(),
    getMonedaPrincipal(),
  ]);

  return (
    <InsumosView
      tipo="insumo"
      insumos={insumos}
      categorias={categorias}
      colores={colores}
      puedeEditar={cargar}
      puedeCostos={costos}
      monedaPrincipal={monedaPrincipal}
    />
  );
}
