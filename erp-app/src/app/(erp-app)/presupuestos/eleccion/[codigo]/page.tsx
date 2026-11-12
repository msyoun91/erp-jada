import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { leerEleccion } from "@/modules/presupuestos/actions";
import { EleccionVista } from "@/modules/presupuestos/components/EleccionView";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";

// El link del mensaje del cliente: lleva el código; la base lo lee, lo valida y dice si quien mira puede armar ese presupuesto.
export default async function EleccionPage(props: PageProps<"/presupuestos/eleccion/[codigo]">) {
  const { codigo } = await props.params;
  if (!(await puedeVerPresupuestos())) notFound();
  const texto = decodeURIComponent(codigo);
  const r = await leerEleccion({ texto });
  return (
    <div className="flex flex-col gap-4">
      {r.success ? (
        <Volver href={`/presupuestos/${r.eleccion.presupuesto_id}`}>{r.eleccion.codigo}</Volver>
      ) : (
        <Volver href="/presupuestos">Presupuestos</Volver>
      )}
      <div className="card flex flex-col gap-3">
        <h2 className="t-h2">Elección del cliente</h2>
        {r.success ? <EleccionVista eleccion={r.eleccion} texto={texto} /> : <p className="alert alert-warning">{r.error}</p>}
      </div>
    </div>
  );
}
