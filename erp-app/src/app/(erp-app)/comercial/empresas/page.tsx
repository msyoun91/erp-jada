import { notFound } from "next/navigation";
import { puedeGestionarEmpresas, puedeVerEmpresas } from "@/modules/comercial/permissions";
import { getEmpresas } from "@/modules/comercial/queries";
import { EmpresasView } from "@/modules/comercial/components/EmpresasView";

export default async function EmpresasPage() {
  if (!(await puedeVerEmpresas())) notFound();

  const [empresas, gestionar] = await Promise.all([getEmpresas(), puedeGestionarEmpresas()]);

  return <EmpresasView empresas={empresas} puedeGestionar={gestionar} />;
}
