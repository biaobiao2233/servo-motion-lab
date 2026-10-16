using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using EnvDTE80;
using TCatSysManagerLib;

// 仅连接指定工程；不构建、不下装、不改变目标或运动命令。
public static class ServoDemoSession
{
    [DllImport("ole32.dll")] static extern int GetRunningObjectTable(int reserved,out IRunningObjectTable rot);
    [DllImport("ole32.dll")] static extern int CreateBindCtx(int reserved,out IBindCtx context);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    static List<DTE2> Windows()
    {
        var result=new List<DTE2>();IRunningObjectTable rot;GetRunningObjectTable(0,out rot);
        IEnumMoniker iterator;rot.EnumRunning(out iterator);IBindCtx context;CreateBindCtx(0,out context);
        var item=new IMoniker[1];
        while(iterator.Next(1,item,IntPtr.Zero)==0)
        {
            string name;item[0].GetDisplayName(context,null,out name);
            if(!name.StartsWith("!TcXaeShell.DTE.17.0:",StringComparison.OrdinalIgnoreCase))continue;
            object value;rot.GetObject(item[0],out value);result.Add((DTE2)value);
        }
        return result;
    }
    public static int Pid(object value){uint pid;GetWindowThreadProcessId(((DTE2)value).MainWindow.HWnd,out pid);return (int)pid;}
    public static object SwitchSaved(int pid,string previous,string solution)
    {
        foreach(var window in Windows())
        {
            if(Pid(window)!=pid)continue;
            if(!string.Equals(window.Solution.FullName,previous,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Existing solution identity changed.");
            for(int i=1;i<=window.Documents.Count;i++)if(!window.Documents.Item(i).Saved)throw new InvalidOperationException("Preserve unsaved documents before switching.");
            window.Solution.Open(Path.GetFullPath(solution));return window;
        }
        throw new InvalidOperationException("Specified existing XAE window was not found.");
    }
    public static object OpenSaved(string solution)
    {
        var path=Path.GetFullPath(solution);var windows=Windows();DTE2 match=null;
        foreach(var window in windows)
            if(string.Equals(window.Solution.FullName,path,StringComparison.OrdinalIgnoreCase))
            {if(match!=null)throw new InvalidOperationException("Multiple copies of the demo are open.");match=window;}
        if(match!=null)return match;
        DTE2 empty=null;
        foreach(var window in windows)if(string.IsNullOrEmpty(window.Solution.FullName))
        {if(empty!=null)throw new InvalidOperationException("Several empty XAE windows are open.");empty=window;}
        if(empty==null && windows.Count!=0)throw new InvalidOperationException("Close the other solution or open the saved demo first; no duplicate window was created.");
        if(empty==null)empty=(DTE2)Activator.CreateInstance(Type.GetTypeFromProgID("TcXaeShell.DTE.17.0",true));
        empty.UserControl=true;empty.MainWindow.Visible=true;empty.Solution.Open(path);return empty;
    }
    public static string LoginAndShow(object value,string solution)
    {
        var window=(DTE2)value;
        if(!string.Equals(window.Solution.FullName,Path.GetFullPath(solution),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Unexpected solution.");
        var manager=(ITcSysManager7)window.Solution.Projects.Item(1).Object;
        if(manager.GetTargetNetId()!="127.0.0.1.10.22")throw new InvalidOperationException("Unexpected Runtime target; refusing to change it.");
        var nested=((ITcProjectRoot)manager.LookupTreeItem("TIPC").LookupChild("ServoPLC")).NestedProject;
        var plc=(ITcPlcOnline)nested;if(!plc.IsLoggedIn)plc.Login((PLC_LOGIN_FLAGS)0);
        window.MainWindow.Visible=true;window.MainWindow.Activate();
        window.ItemOperations.OpenFile(Path.Combine(Path.GetDirectoryName(solution),"ServoConfiguration","ServoPLC","VISUs","ServoDashboard.TcVIS"));
        // 收起停靠窗格，给演示画布留足空间；不清除错误记录。
        foreach(var kind in new[]{EnvDTE.Constants.vsWindowKindProperties,EnvDTE.Constants.vsWindowKindToolbox,EnvDTE80.WindowKinds.vsWindowKindErrorList,EnvDTE.Constants.vsWindowKindOutput})
            try{window.Windows.Item(kind).Visible=false;}catch(COMException){}
        return "LoggedIn="+plc.IsLoggedIn+" State="+plc.OnlineApplicationState;
    }
}
