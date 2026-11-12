import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { idSchema } from "@/lib/validacion";
import { puedeArmar } from "@/modules/presupuestos/permissions";
import { getEleccion } from "@/modules/presupuestos/queries";
import { EleccionView } from "@/modules/presupuestos/components/EleccionView";

function decodificar(segmento: string) {
  try {
    return decodeURIComponent(segmento);
  } catch {
    return segmento;
  }
}

// El segmento es el código o el mensaje entero que pegó Juan: la base busca el código en el texto.
export default async function EleccionPage(props: PageProps<"/presupuestos/eleccion/[codigo]">) {
  const [{ codigo }, { desde }] = await Promise.all([props.params, props.searchParams]);
  if (!(await puedeArmar())) notFound();
  const texto = decodificar(codigo);
  const resultado = await getEleccion(texto);
  if (!resultado) notFound();
  const presupuesto = typeof desde === "string" && idSchema.safeParse(desde).success ? desde : null;
  return (
    <div className="flex flex-col gap-4">
      <Volver href="/presupuestos">Presupuestos</Volver>
      <EleccionView texto={texto} resultado={resultado} desde={presupuesto} />
    </div>
  );
}
