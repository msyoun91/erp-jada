import { notFound } from "next/navigation";
import { puedeRevisar } from "@/modules/presupuestos/permissions";
import { getRevisionPendientes } from "@/modules/presupuestos/queries";
import { RevisionView } from "@/modules/presupuestos/components/RevisionView";

export default async function RevisionPage() {
  if (!(await puedeRevisar())) notFound();
  return <RevisionView pendientes={await getRevisionPendientes()} />;
}
