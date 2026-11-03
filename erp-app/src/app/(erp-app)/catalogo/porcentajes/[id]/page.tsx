import { notFound } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { puedeEditarPorcentajes, puedeVerPorcentajes } from "@/modules/catalogo/permissions";
import { getCategorias, getMonedaPrincipal, getPorcentajeHistoria, getPorcentajes } from "@/modules/catalogo/queries";
import { PorcentajeFicha } from "@/modules/catalogo/components/PorcentajeFicha";

export default async function PorcentajePage(props: PageProps<"/catalogo/porcentajes/[id]">) {
  const { id } = await props.params;
  if (!(await puedeVerPorcentajes()) || !idSchema.safeParse(id).success) notFound();

  const [porcentajes, historia, categoriasInsumo, categoriasServicio, editar, monedaPrincipal] = await Promise.all([
    getPorcentajes(),
    getPorcentajeHistoria(id),
    getCategorias("insumo"),
    getCategorias("servicio"),
    puedeEditarPorcentajes(),
    getMonedaPrincipal(),
  ]);
  const porcentaje = porcentajes.find((p) => p.id === id);
  if (!porcentaje) notFound();

  return (
    <PorcentajeFicha
      porcentaje={porcentaje}
      historia={historia}
      categoriasInsumo={categoriasInsumo}
      categoriasServicio={categoriasServicio}
      puedeEditar={editar}
      monedaPrincipal={monedaPrincipal}
    />
  );
}
