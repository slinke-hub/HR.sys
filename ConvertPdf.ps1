Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Data.Pdf;
using Windows.Storage;
using Windows.Storage.Streams;

public class PdfConverter {
    public static async Task ConvertFirstPageAsync(string pdfPath, string pngPath) {
        StorageFile file = await StorageFile.GetFileFromPathAsync(pdfPath);
        PdfDocument doc = await PdfDocument.LoadFromFileAsync(file);
        PdfPage page = doc.GetPage(0);
        
        using (InMemoryRandomAccessStream stream = new InMemoryRandomAccessStream()) {
            PdfPageRenderOptions opts = new PdfPageRenderOptions();
            opts.DestinationWidth = 2480; // A4 at 300dpi
            
            await page.RenderToStreamAsync(stream, opts);
            
            using (Stream readStream = stream.AsStreamForRead())
            using (FileStream fileStream = File.Create(pngPath)) {
                await readStream.CopyToAsync(fileStream);
            }
        }
    }
}
"@

$pdfPath = "C:\Users\ASUS\.gemini\antigravity-ide\brain\d8304e86-72a0-4d19-8dcb-5709622b5d86\media__1786538464398.pdf"
$pngPath = "e:\HR.sys\images\letterhead.png"

[PdfConverter]::ConvertFirstPageAsync($pdfPath, $pngPath).GetAwaiter().GetResult()
Write-Host "Done!"
