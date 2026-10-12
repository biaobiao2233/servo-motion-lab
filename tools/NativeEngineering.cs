using System;
using System.IO;
using System.Runtime.InteropServices;
using TCatSysManagerLib;
using EnvDTE80;
using System.Collections.Generic;
using System.Xml.Linq;

public static class ServoNativeEngineering
{
    private const string DemoPlatform = "TwinCAT OS (x64)";
    public static string[] CreateAxisAndPlc(object systemManager, string sourceDirectory, string evidenceDirectory)
    {
        // 在 C# 中按 COM IID 转换，避免 PowerShell 对 RCW 的类型转换差异。
        var manager = (ITcSysManager7)systemManager;
        manager.SetTargetNetId("127.0.0.1.10.22");
        var config = (ITcConfigManager)manager.ConfigurationManager;
        File.WriteAllLines(Path.Combine(evidenceDirectory, "target-platforms.txt"), config.TargetPlatforms);
        config.ActiveTargetPlatform = DemoPlatform;
        var motion = manager.LookupTreeItem("TINC");
        var task = motion.CreateChild("NC-Task", 1, "", null);
        var axis = task.LookupChild("Axes").CreateChild("ServoAxis", 1, "", null);
        axis.ConsumeXml("<TreeItem><NcAxisDef><AxisParam><Unit>mm</Unit><Dynamic><Acceleration>80</Acceleration><Deceleration>80</Deceleration><Jerk>400</Jerk></Dynamic><Velo><Fast>50</Fast><Maximum>50</Maximum></Velo><TargetPosControl><Enable>true</Enable><Range>0.01</Range><Time>0.02</Time></TargetPosControl></AxisParam><Encoder><EncParam><SoftEndMinControl><Enable>true</Enable><Range>0</Range></SoftEndMinControl><SoftEndMaxControl><Enable>true</Enable><Range>100</Range></SoftEndMaxControl></EncParam></Encoder></NcAxisDef></TreeItem>");
        File.WriteAllText(Path.Combine(evidenceDirectory, "axis-default.xml"), axis.ProduceXml(false));
        var plc = manager.LookupTreeItem("TIPC").CreateChild("ServoPLC", 0, "", "Empty PLC Template");
        var nested = ((ITcProjectRoot)plc).NestedProject;
        var references = nested.LookupChild("References");
        var libraries = (ITcPlcLibraryManager)references;
        libraries.AddLibrary("Tc2_Standard", "3.4.7.0", "Beckhoff Automation GmbH");
        libraries.AddLibrary("Tc2_System", "3.10.2.0", "Beckhoff Automation GmbH");
        libraries.AddLibrary("Tc3_Module", "3.4.7.0", "Beckhoff Automation GmbH");
        libraries.AddLibrary("Tc2_MC2", "3.3.75.0", "Beckhoff Automation GmbH");
        var pous = nested.CreateChild("POUs",601,"",null);
        var gvls = nested.CreateChild("GVLs",601,"",null);
        foreach (string name in new[] { "GVL_Command", "GVL_Motion", "GVL_Monitor", "GVL_Hmi" })
        {
            var item = gvls.CreateChild(name,615,"",null);
            ((ITcPlcDeclaration)item).DeclarationText = File.ReadAllText(Path.Combine(sourceDirectory,name+".st"));
        }
        CreatePou(pous,"FB_ServoAxis",604,sourceDirectory);
        CreatePou(pous,"FB_HmiAdapter",604,sourceDirectory);
        CreatePou(pous,"MAIN",602,sourceDirectory);
        var visuSource=Path.Combine(Path.GetDirectoryName(sourceDirectory),"visu","ServoDashboard.TcVIS");
        if(File.Exists(visuSource))
        {
            var visus=nested.CreateChild("VISUs",601,"",null);
            // 58 imports an existing native PLC object; the file determines its visualization type.
            visus.CreateChild("ServoDashboard",58,"",visuSource);
        }
        var systemTask = manager.LookupTreeItem("TIRT").CreateChild("ServoTask",1,"",null);
        systemTask.ConsumeXml("<TreeItem><TaskDef><CycleTime>50000</CycleTime><Priority>20</Priority></TaskDef></TreeItem>");
        var plcTask = nested.CreateChild("ServoTask",621,"","MAIN");
        ((ITcPlcTaskReference)plcTask).LinkedTask = systemTask.PathName;
        return new[] { axis.PathName, nested.PathName, manager.GetTargetNetId() };
    }

    private static void CreatePou(ITcSmTreeItem parent, string name, int subtype, string sourceDirectory)
    {
        var item = parent.CreateChild(name,subtype,"",new object[] { 1 });
        ((ITcPlcDeclaration)item).DeclarationText = File.ReadAllText(Path.Combine(sourceDirectory,name+".decl.st"));
        ((ITcPlcImplementation)item).ImplementationText = File.ReadAllText(Path.Combine(sourceDirectory,name+".impl.st"));
    }

    public static void ExportPlcInstance(object systemManager, string evidenceDirectory)
    {
        var manager=(ITcSysManager7)systemManager;
        var plc=manager.LookupTreeItem("TIPC").LookupChild("ServoPLC");
        File.WriteAllText(Path.Combine(evidenceDirectory,"plc-root.xml"),plc.ProduceXml(true));
        File.WriteAllText(Path.Combine(evidenceDirectory,"nc-tree.xml"),manager.LookupTreeItem("TINC").ProduceXml(true));
    }

    public static string[] SelectBuildConfiguration(object dteObject)
    {
        var dte=(DTE2)dteObject;
        var configs=dte.Solution.SolutionBuild.SolutionConfigurations;
        for(int i=1;i<=configs.Count;i++)
        {
            var cfg=(SolutionConfiguration2)configs.Item(i);
            if(cfg.Name=="Release" && cfg.PlatformName==DemoPlatform)
            {
                cfg.Activate();
                var contexts=cfg.SolutionContexts;
                var result=new string[contexts.Count];
                for(int j=1;j<=contexts.Count;j++)
                {
                    var context=contexts.Item(j);
                    if(!context.ShouldBuild) throw new InvalidOperationException("A demo project is excluded from native build: "+context.ProjectName);
                    result[j-1]=context.ProjectName+" | ShouldBuild=True";
                }
                return result;
            }
        }
        throw new InvalidOperationException("Missing Release/"+DemoPlatform+" configuration.");
    }

    public static void SynchronizeSources(object systemManager,string sourceDirectory)
    {
        if(systemManager==null) throw new InvalidOperationException("The TwinCAT project object is not ready.");
        var manager=(ITcSysManager7)systemManager;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22") throw new InvalidOperationException("Unexpected demo target.");
        ((ITcConfigManager)manager.ConfigurationManager).ActiveTargetPlatform=DemoPlatform;
        var plc=manager.LookupTreeItem("TIPC").LookupChild("ServoPLC");
        if(plc==null) throw new InvalidOperationException("The owned PLC root is unavailable.");
        var nested=((ITcProjectRoot)plc).NestedProject;
        if(nested==null) throw new InvalidOperationException("The owned nested PLC project is unavailable.");
        foreach(string name in new[] { "GVL_Command", "GVL_Motion", "GVL_Monitor", "GVL_Hmi" })
            ((ITcPlcDeclaration)EnsureChild(nested.LookupChild("GVLs"),name,615,null)).DeclarationText=File.ReadAllText(Path.Combine(sourceDirectory,name+".st"));
        foreach(string name in new[] { "FB_ServoAxis", "FB_HmiAdapter", "MAIN" })
        {
            var item=EnsureChild(nested.LookupChild("POUs"),name,name=="MAIN"?602:604,new object[] {1});
            ((ITcPlcDeclaration)item).DeclarationText=File.ReadAllText(Path.Combine(sourceDirectory,name+".decl.st"));
            ((ITcPlcImplementation)item).ImplementationText=File.ReadAllText(Path.Combine(sourceDirectory,name+".impl.st"));
        }
    }

    private static ITcSmTreeItem EnsureChild(ITcSmTreeItem parent,string name,int subtype,object info)
    {
        for(int i=1;i<=parent.ChildCount;i++) if(parent.Child[i].Name==name) return parent.Child[i];
        return parent.CreateChild(name,subtype,"",info);
    }

    public static string CaptureBuildEvidence(object dteObject,string evidenceDirectory)
    {
        var dte=(DTE2)dteObject;
        var diagnostics=new XElement("Diagnostics");
        var items=dte.ToolWindows.ErrorList.ErrorItems;
        for(int i=1;i<=items.Count;i++)
        {
            var item=items.Item(i);
            diagnostics.Add(new XElement("Diagnostic",new XAttribute("Level",(int)item.ErrorLevel),
                new XAttribute("File",item.FileName??""),new XAttribute("Line",item.Line),
                new XElement("Description",item.Description)));
        }
        diagnostics.Save(Path.Combine(evidenceDirectory,"native-diagnostics.xml"));
        dte.ExecuteCommand("View.Output","");
        var panes=dte.ToolWindows.OutputWindow.OutputWindowPanes;
        var text=new System.Text.StringBuilder();
        for(int i=1;i<=panes.Count;i++)
        {
            var pane=panes.Item(i);
            text.AppendLine("Pane: "+pane.Name);
            try {
                var doc=pane.TextDocument;
                text.AppendLine(doc.StartPoint.CreateEditPoint().GetText(doc.EndPoint));
            }catch(Exception ex){text.AppendLine("Output read failed: "+ex.Message);}
        }
        File.WriteAllText(Path.Combine(evidenceDirectory,"native-build-output.log"),text.ToString());
        return diagnostics.ToString();
    }

    public static bool CheckPlcObjects(object systemManager)
    {
        var manager=(ITcSysManager7)systemManager;
        var plc=manager.LookupTreeItem("TIPC").LookupChild("ServoPLC");
        var nested=((ITcProjectRoot)plc).NestedProject;
        return ((ITcPlcIECProject2)nested).CheckAllObjects();
    }

    public static void PrepareDemoBoot(object systemManager)
    {
        var manager=(ITcSysManager7)systemManager;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22") throw new InvalidOperationException("Refusing unexpected activation target.");
        var plc=(ITcPlcProject)manager.LookupTreeItem("TIPC").LookupChild("ServoPLC");
        plc.BootProjectAutostart=true;
    }

    public static void ActivateDemoConfiguration(object systemManager)
    {
        var manager=(ITcSysManager7)systemManager;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22") throw new InvalidOperationException("Refusing unexpected activation target.");
        manager.ActivateConfiguration();
    }

    public static void RestartDemoRuntime(object systemManager)
    {
        var manager=(ITcSysManager7)systemManager;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22") throw new InvalidOperationException("Refusing unexpected restart target.");
        manager.StartRestartTwinCAT();
    }

    public static string GetDemoErrors(object systemManager)
    {
        var manager=(ITcSysManager7)systemManager;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22") throw new InvalidOperationException("Unexpected diagnostics target.");
        return manager.GetLastErrorMessages();
    }

    public static string ReadTarget(object systemManager)
    {
        return ((ITcSysManager7)systemManager).GetTargetNetId();
    }

    public static void SelectDemoTarget(object systemManager)
    {
        ((ITcSysManager7)systemManager).SetTargetNetId("127.0.0.1.10.22");
    }

    public static string BindAxis(object systemManager,string evidenceDirectory)
    {
        var manager=(ITcSysManager7)systemManager;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22") throw new InvalidOperationException("Refusing unexpected target.");
        var nc=manager.LookupTreeItem("TINC").get_Child(1);
        var axis=nc.LookupChild("Axes").LookupChild("ServoAxis");
        var plc=manager.LookupTreeItem("TIPC").LookupChild("ServoPLC");
        File.WriteAllText(Path.Combine(evidenceDirectory,"nc-task.xml"),nc.ProduceXml(true));
        // 中文 XAE 把轴过程映像组命名为「输入 / 输出」，英文安装仍是 Inputs / Outputs。
        var sourceToPlc=FirstExisting(manager, axis.PathName+"^输出^ToPlc", axis.PathName+"^Outputs^ToPlc");
        var sourceFromPlc=FirstExisting(manager, axis.PathName+"^输入^FromPlc", axis.PathName+"^Inputs^FromPlc");
        var plcInput=FirstExisting(manager, plc.PathName+"^ServoPLC Instance^ServoTask Inputs^GVL_Motion.Axis.NcToPlc");
        var plcOutput=FirstExisting(manager, plc.PathName+"^ServoPLC Instance^ServoTask Outputs^GVL_Motion.Axis.PlcToNc");
        manager.LinkVariables(sourceToPlc,plcInput,0,0,0);
        manager.LinkVariables(plcOutput,sourceFromPlc,0,0,0);
        return sourceToPlc+" -> "+plcInput+"\n"+plcOutput+" -> "+sourceFromPlc;
    }

    private static string FirstExisting(ITcSysManager7 manager, params string[] paths)
    {
        COMException last=null;
        foreach(string path in paths)
        {
            try
            {
                var item=manager.LookupTreeItem(path);
                if(item!=null) return item.PathName;
            }
            catch(COMException ex){ last=ex; }
        }
        throw new InvalidOperationException("Missing mapping endpoint: "+string.Join(" | ", paths), last);
    }
}
