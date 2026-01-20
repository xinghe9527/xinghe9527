// Xinghe Launcher - 启动器
// 作用：隐藏 Flutter 和其他技术细节
// 编译：g++ -O2 -s -static -o xinghe.exe xinghe_launcher.cpp -mwindows

#include <windows.h>
#include <string>

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
    // 获取启动器所在目录
    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, MAX_PATH);
    
    std::string exeDir = exePath;
    size_t pos = exeDir.find_last_of("\\/");
    if (pos != std::string::npos) {
        exeDir = exeDir.substr(0, pos);
    }
    
    // 构建真实程序路径（在 bin 子目录）
    std::string realAppPath = exeDir + "\\bin\\xinghe_app.exe";
    
    // 设置工作目录为 bin 目录（让程序能找到 DLL）
    std::string binDir = exeDir + "\\bin";
    SetCurrentDirectoryA(binDir.c_str());
    
    // 启动真实程序
    STARTUPINFOA si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    
    if (CreateProcessA(
        realAppPath.c_str(),    // 程序路径
        lpCmdLine,              // 命令行参数
        NULL,                   // 进程安全属性
        NULL,                   // 线程安全属性
        FALSE,                  // 继承句柄
        0,                      // 创建标志
        NULL,                   // 环境变量
        binDir.c_str(),         // 工作目录
        &si,                    // 启动信息
        &pi                     // 进程信息
    )) {
        // 等待程序结束
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        // 获取退出码
        DWORD exitCode;
        GetExitCodeProcess(pi.hProcess, &exitCode);
        
        // 清理句柄
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        
        return exitCode;
    } else {
        MessageBoxA(NULL, 
            "无法启动应用程序。\n请尝试重新安装。", 
            "启动错误", 
            MB_OK | MB_ICONERROR);
        return 1;
    }
}
