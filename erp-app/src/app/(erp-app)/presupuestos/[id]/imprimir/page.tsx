import { cache } from "react";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Volver } from "@/components/ui/Volver";
import { hoyISO } from "@/lib/utils";
import { idSchema } from "@/lib/validacion";
import { getVinculosDe } from "@/modules/contactos/queries";
import { puedeVerPresupuestos } from "@/modules/presupuestos/permissions";
import { getImpreso } from "@/modules/presupuestos/queries";
import { Imprimir } from "@/modules/presupuestos/components/Imprimir";
import { ImpresoView } from "@/modules/presupuestos/components/ImpresoView";

const impreso = cache(async (id: string) =>
  idSchema.safeParse(id).success && (await puedeVerPresupuestos()) ? getImpreso(id) : null,
);

// El título es el nombre que el navegador propone al guardar como PDF: "P-0142 · Torre Belgrano.pdf".
export async function generateMetadata(props: PageProps<"/presupuestos/[id]/imprimir">): Promise<Metadata> {
  const datos = await impreso((await props.params).id);
  return { title: datos ? `${datos.presupuesto.codigo} · ${datos.presupuesto.nombre}` : "ERP JADA" };
}

export default async function ImprimirPage(props: PageProps<"/presupuestos/[id]/imprimir">) {
  const { id } = await props.params;
  const datos = await impreso(id);
  if (!datos) notFound();
  // Los contactos con rol cliente, abiertos; el que quien mira no ve como contacto, no sale.
  const clientes = (await getVinculosDe("obra", datos.presupuesto.obra.id))
    .filter((v) => v.hasta === null && v.roles.includes("cliente"))
    .flatMap((v) => {
      const nombre = v.contactos_personas?.nombre ?? v.contactos_empresas?.nombre;
      return nombre ? [nombre] : [];
    });
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Volver href={`/presupuestos/${id}`}>{datos.presupuesto.codigo}</Volver>
        {datos.versiones.length > 0 && <Imprimir />}
      </div>
      {datos.versiones.length > 0 ? (
        <ImpresoView impreso={datos} clientes={clientes} hoy={hoyISO()} />
      ) : (
        <p className="empty-state">Un borrador no se imprime: primero se publica.</p>
      )}
    </div>
  );
}
