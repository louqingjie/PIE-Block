package cn.edu.cnu.pieblock_app;

import android.os.Bundle;
import cn.edu.cnu.pieblock_app.ISdccCompilerCallback;

interface ISdccCompilerService {
    int protocolVersion();
    Bundle capabilities();
    String start(in Bundle request, ISdccCompilerCallback callback);
    void cancel(String operationId);
    void acknowledge(String operationId);
}
