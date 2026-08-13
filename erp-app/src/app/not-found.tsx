import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-full flex-1 items-center justify-center bg-bg-page p-4">
      <div className="text-center">
        <p className="font-display text-display-l text-text-primary">404</p>
        <p className="t-body-m mt-2">No encontramos esta página, o no tenés acceso.</p>
        <Link href="/" className="btn btn-primary mt-6 inline-flex">
          Volver al inicio
        </Link>
      </div>
    </div>
  );
}
