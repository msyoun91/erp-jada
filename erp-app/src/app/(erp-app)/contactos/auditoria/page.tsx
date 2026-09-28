import { notFound } from "next/navigation";
import { DIAS_OPCIONES } from "@/components/ui/FiltroDias";
import { idSchema } from "@/lib/validacion";
import { puedeAuditar } from "@/modules/contactos/permissions";
import { getAuditoriaDetalle, getAuditoriaResumen } from "@/modules/contactos/queries";
import { AuditoriaView } from "@/modules/contactos/components/AuditoriaView";

// La vista Auditoría (`contactos_auditoria`), sin requerir `contactos_ver`.
export default async function AuditoriaPage(props: PageProps<"/contactos/auditoria">) {
  if (!(await puedeAuditar())) notFound();

  const { dias: diasParam, usuario: u, persona: p } = await props.searchParams;
  const dias = DIAS_OPCIONES.includes(Number(diasParam)) ? Number(diasParam) : 30;
  const usuario = idSchema.safeParse(u).success ? (u as string) : null;
  const persona = idSchema.safeParse(p).success ? (p as string) : null;

  const [resumen, detalle] = await Promise.all([
    getAuditoriaResumen(dias),
    usuario || persona ? getAuditoriaDetalle(dias, usuario, persona) : null,
  ]);

  return <AuditoriaView dias={dias} usuario={usuario} persona={persona} resumen={resumen} detalle={detalle} />;
}
