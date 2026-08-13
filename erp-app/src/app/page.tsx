import Image from "next/image";

export default function Home() {
  return (
    <div className="flex flex-1 items-center justify-center bg-bg-page">
      <div className="flex flex-col items-center gap-4">
        <Image src="/logo.svg" alt="JADA" width={181} height={66} priority />
        <p className="t-body-m">ERP JADA</p>
      </div>
    </div>
  );
}
