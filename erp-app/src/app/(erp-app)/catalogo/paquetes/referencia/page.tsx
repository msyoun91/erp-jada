import { notFound } from "next/navigation";
import { DIAS_OPCIONES } from "@/components/ui/FiltroDias";
import { puedeAprobar, puedeVerPaquetes } from "@/modules/catalogo/permissions";
import { getMonedaPrincipal, getPreciosReferencia } from "@/modules/catalogo/queries";
import { ReferenciaView } from "@/modules/catalogo/components/ReferenciaView";

export default async function ReferenciaPage(props: PageProps<"/catalogo/paquetes/referencia">) {
  if (!(await puedeVerPaquetes()) || !(await puedeAprobar())) notFound();
  const { dias: diasParam } = await props.searchParams;
  const dias = DIAS_OPCIONES.includes(Number(diasParam)) ? Number(diasParam) : 30;
  const moneda = await getMonedaPrincipal();
  const filas = await getPreciosReferencia(moneda, dias);

  return <ReferenciaView filas={filas} dias={dias} moneda={moneda} />;
}
