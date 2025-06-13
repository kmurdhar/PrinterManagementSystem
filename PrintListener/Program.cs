using System;
using System.Management;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Security.Principal;
using System.IO;

namespace PrintMonitor
{
    public class PrintJob
    {
        public string JobId { get; set; }
        public string UserName { get; set; }
        public string MachineName { get; set; }
        public string PrinterName { get; set; }
        public string DocumentName { get; set; }
        public int PageCount { get; set; }
        public DateTime PrintTime { get; set; }
        public string Status { get; set; }
        public long FileSize { get; set; }
    }

    public class PrintListener
    {
        private readonly HttpClient _httpClient;
        private readonly string _apiEndpoint;
        private ManagementEventWatcher _watcher;

        public PrintListener(string apiEndpoint = "http://localhost:3000/api/print-jobs")
        {
            _httpClient = new HttpClient();
            _apiEndpoint = apiEndpoint;
        }

        public void StartMonitoring()
        {
            try
            {
                // Monitor print job events using WMI
                var query = new WqlEventQuery(
                    "SELECT * FROM Win32_PrintJob WHERE TargetInstance ISA 'Win32_PrintJob'");
                
                _watcher = new ManagementEventWatcher(query);
                _watcher.EventArrived += OnPrintJobEvent;
                _watcher.Start();

                Console.WriteLine("Print monitoring started. Press 'q' to quit.");
                
                while (Console.ReadKey().KeyChar != 'q')
                {
                    System.Threading.Thread.Sleep(100);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error starting print monitor: {ex.Message}");
            }
        }

        private async void OnPrintJobEvent(object sender, EventArrivedEventArgs e)
        {
            try
            {
                var targetInstance = e.NewEvent["TargetInstance"] as ManagementBaseObject;
                if (targetInstance == null) return;

                var printJob = new PrintJob
                {
                    JobId = targetInstance["JobId"]?.ToString(),
                    UserName = targetInstance["Owner"]?.ToString() ?? GetCurrentUser(),
                    MachineName = Environment.MachineName,
                    PrinterName = targetInstance["PrinterName"]?.ToString(),
                    DocumentName = targetInstance["Document"]?.ToString(),
                    PageCount = Convert.ToInt32(targetInstance["TotalPages"] ?? 0),
                    PrintTime = DateTime.Now,
                    Status = targetInstance["JobStatus"]?.ToString() ?? "Unknown",
                    FileSize = Convert.ToInt64(targetInstance["Size"] ?? 0)
                };

                await SendPrintJobToAPI(printJob);
                Console.WriteLine($"Print job captured: {printJob.DocumentName} by {printJob.UserName}");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error processing print job: {ex.Message}");
            }
        }

        private async Task SendPrintJobToAPI(PrintJob printJob)
        {
            try
            {
                var json = JsonSerializer.Serialize(printJob);
                var content = new StringContent(json, Encoding.UTF8, "application/json");
                
                var response = await _httpClient.PostAsync(_apiEndpoint, content);
                
                if (!response.IsSuccessStatusCode)
                {
                    Console.WriteLine($"Failed to send print job to API: {response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error sending to API: {ex.Message}");
            }
        }

        private string GetCurrentUser()
        {
            try
            {
                return WindowsIdentity.GetCurrent().Name;
            }
            catch
            {
                return "Unknown";
            }
        }

        public void Stop()
        {
            _watcher?.Stop();
            _watcher?.Dispose();
        }
    }

    class Program
    {
        static void Main(string[] args)
        {
            var listener = new PrintListener();
            listener.StartMonitoring();
            listener.Stop();
        }
    }
}