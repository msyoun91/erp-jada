import { notFound, redirect } from "next/navigation";
import { idSchema } from "@/lib/validacion";
import { puedeVerContactos } from "@/modules/contactos/permissions";
import { getFusionada } from "@/modules/contactos/queries";
import { fichaEmpresa } from "./ficha";

export default async function EmpresaPage(props: PageProps<"/contactos/empresas/[id]">) {
  const { id } = await props.params;
  if (!idSchema.safeParse(id).success) notFound();
  const ficha = await fichaEmpresa(id);
  if (ficha) return ficha;
  const fusionada = (await puedeVerContactos()) ? await getFusionada("empresa", id) : null;
  if (fusionada?.id) redirect(`/contactos/empresas/${fusionada.id}`);
  notFound();
}
